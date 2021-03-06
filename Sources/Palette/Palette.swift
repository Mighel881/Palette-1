//
//  Palette.swift
//
//  Created by Alfonso Gonzalez on 4/9/20.
//  Copyright (c) 2020 Alfonso Gonzalez

#if os(macOS)
    import AppKit
    public typealias UIImage = NSImage
    public typealias UIColor = NSColor
#else
    import UIKit
#endif

// MARK: Public API

/// A structure that describes a `UIImage`'s color palette.
///
/// This structure provides the three most prominent colors in a `UIImage`. Since images can contain less than
/// three colors, you must be able to adapt to such images.
public struct UIImageColorPalette: CustomStringConvertible {
    /// The color most prevalent in the image
    let primary: UIColor
    
    /// The second most prevalent color in the image
    let secondary: UIColor?
    
    /// The third most prevalent color in the image
    let tertiary: UIColor?
    
    public init(primary: UIColor, secondary: UIColor?, tertiary: UIColor?) {
        self.primary = primary
        self.secondary = secondary
        self.tertiary = tertiary
    }
    
    public var description: String {
        var description = "Primary: \(primary)"
        
        if let secondary = secondary {
            description += ", Secondary: \(secondary)"
        }
        
        if let tertiary = tertiary {
            description += ", Tertiary: \(tertiary)"
        }
        
        return description
    }
}

/// The quality associated with resizing an image
///
/// When processing large images, you may want to resize the image in order to speed up the processing.
/// The smaller you resize an image however, you give up more quality and color accuracy potentially.
public enum UIImageResizeQuality: CGFloat {
    /// Quality associated with resizing the image to **0.3x** its size
    case low = 0.3
    
    /// Quality associated with resizing the image to **0.5x** its original size
    case medium = 0.5
    
    /// Quality associated with resizing the image to **0.8x** its original size
    case high = 0.8
    
    /// Quality associated with the original image size
    case standard = 1.0
}

extension UIImage {
    #if os(macOS)
        private func resizeImage(desiredSize: CGSize) -> UIImage? {
            if desiredSize == size {
                return self
            }
            
            let frame = CGRect(origin: .zero, size: desiredSize)
            guard let representation = bestRepresentation(for: frame, context: nil, hints: nil) else {
                return nil
            }
            
            let result = NSImage(size: desiredSize, flipped: false) { (_) -> Bool in
                return representation.draw(in: frame)
            }
            
            return result
        }
    #else
        private func resizeImage(desiredSize: CGSize) -> UIImage? {
            if desiredSize == size {
                return self
            }
            
            // Make sure scale remains the same
            let format = UIGraphicsImageRendererFormat()
            format.scale = scale

            // UIGraphicsImageRenderer makes life easy
            let renderer = UIGraphicsImageRenderer(size: desiredSize, format: format)
            return renderer.image { (context) in
                self.draw(in: CGRect(origin: .zero, size: desiredSize))
            }
        }
    #endif
    
    /// Queues the creation of the `UIImageColorPalette` object onto a background queue.
    ///
    /// - Parameters:
    ///   - quality: Quality to resize image. The default value is `.standard`.
    ///   - completion: Completion to call with the resulting `UIImageColorPalette` object.
    ///   - palette: The calculated `UIImageColorPalette` object.
    ///
    /// When processing large images, you may want dispatch the task to a background thread in order to distribute out the load.
    /// This method dispatches the processing onto a seperate queue, and returns the calculated `UIImageColorPalette` in the completion.
    public func retrieveColorPalette(quality: UIImageResizeQuality = .standard, completion: @escaping (_ palette: UIImageColorPalette?) -> Void) {
        // Run in background
        DispatchQueue.global(qos: .utility).async {
            let palette = self.retrieveColorPalette(quality: quality)
            
            // Back to main
            DispatchQueue.main.async {
                completion(palette)
            }
        }
    }
    
    /// Returns the color palette of an image in the form of a `UIImageColorPalette` object
    ///
    /// - Parameter quality: Quality to resize image. The default value is `.standard`.
    ///
    /// - Returns: A `UIImageColorPalette` object of the color palette.
    public func retrieveColorPalette(quality: UIImageResizeQuality = .standard) -> UIImageColorPalette? {
        // Resize if needed
        var desiredSize = size
        if quality != .standard {
            // Determine new size
            desiredSize = CGSize(width: size.width * quality.rawValue, height: size.height * quality.rawValue)
        }
        
        guard let imageToProcess = resizeImage(desiredSize: desiredSize) else {
            return nil
        }
        
        // Get image data
        #if os(macOS)
            guard let cgImage = imageToProcess.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                return nil
            }
        #else
            guard let cgImage = imageToProcess.cgImage else {
                return nil
            }
        #endif
        
        guard let imageData = CFDataGetBytePtr(cgImage.dataProvider!.data) else {
            fatalError("Could not retrieve image data")
        }
        
        // Create our array of pixels
        let width = cgImage.width
        let height = cgImage.height
        
        var pixels = [Pixel]()
        pixels.reserveCapacity(width * height)
        for x in 0..<width {
            for y in 0..<height {
                // Construct pixel
                let pixelIndex = ((width * y) + x) * 4
                let pixel = Pixel(r: Double(imageData[pixelIndex]), g: Double(imageData[pixelIndex + 1]), b: Double(imageData[pixelIndex + 2]), a: Double(imageData[pixelIndex + 3]))
                pixels.append(pixel)
            }
        }
        
        // Process by k-means clustering
        let analyzer = KMeans(clusterNumber: 3, tolerance: 0.01, dataPoints: pixels)
        let prominentPixels = analyzer.calculateProminentClusters()
        
        // Create palette object
        guard let primaryColor = UIColor(pixel: prominentPixels[0]) else {
            return nil
        }

        let secondaryColor = UIColor(pixel: prominentPixels[1])
        let tertiaryColor = UIColor(pixel: prominentPixels[2])
        return UIImageColorPalette(primary: primaryColor, secondary: secondaryColor, tertiary: tertiaryColor)
    }
}


// MARK: Private Helpers

fileprivate struct Pixel {
    var r: Double
    var g: Double
    var b: Double
    var a: Double
    var count = 0

    init(r: Double, g: Double, b: Double, a: Double) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }
    
    func distanceTo(_ other: Pixel) -> Double {
        // Simple distance formula
        let rDistance = pow(r - other.r, 2)
        let gDistance = pow(g - other.g, 2)
        let bDistance = pow(b - other.b, 2)
        let aDistance = pow(a - other.a, 2)
        
        return sqrt(rDistance + gDistance + bDistance + aDistance)
    }
    
    mutating func append(_ pixel: Pixel) {
        // Add data
        r += pixel.r
        g += pixel.g
        b += pixel.b
        a += pixel.a
    }
    
    mutating func averageOut(count: Int) {
        // Add to count and average
        self.count = count
        r /= Double(count)
        g /= Double(count)
        b /= Double(count)
        a /= Double(count)
    }
}

fileprivate extension UIColor {
    convenience init?(pixel: Pixel) {
        guard !pixel.r.isNaN else {
            return nil
        }
        
        self.init(red: CGFloat(pixel.r / 255), green: CGFloat(pixel.g / 255), blue: CGFloat(pixel.b / 255), alpha: CGFloat(pixel.a / 255))
    }
}

fileprivate class KMeans {
    let clusterNumber: Int
    let tolerance: Double
    let dataPoints: [Pixel]
    
    init(clusterNumber: Int, tolerance: Double, dataPoints: [Pixel]) {
        self.clusterNumber = clusterNumber
        self.tolerance = tolerance
        self.dataPoints = dataPoints
    }
    
    func generateInitialCenters(_ samples: [Pixel], k: Int) -> [Pixel] {
        // Get first center at random
        let random = Int.random(in: 0..<samples.count)
        var centers = [samples[random]]
        
        // Generate the remaining k-1 centers
        for _ in 1..<k {
            var centerCandidate = Pixel(r: 0, g: 0, b: 0, a: 0)
            var furthestDistance = Double.leastNormalMagnitude
            for pixel in samples {
                var distance = Double.greatestFiniteMagnitude
                for center in centers {
                    distance = min(center.distanceTo(pixel), distance)
                }
                
                if distance <= furthestDistance {
                    continue
                }
                
                furthestDistance = distance
                centerCandidate = pixel
            }
            
            centers.append(centerCandidate)
        }
        
        return centers
    }
    
    private func indexOfNearestCentroid(_ pixel: Pixel, centroids: [Pixel]) -> Int {
        var smallestDistance = Double.greatestFiniteMagnitude
        var index = 0

        for (i, centroid) in centroids.enumerated() {
            let distance = pixel.distanceTo(centroid)
            if distance >= smallestDistance {
                // Not the smallest
                continue
            }
            
            smallestDistance = distance
            index = i
        }

        return index
    }
    
    func kMeans(partitions: Int, tolerance: Double, entries: [Pixel]) -> [Pixel] {
        // The main engine behind the scenes
        var centroids = generateInitialCenters(entries, k: partitions)
        
        var centerMoveDist = 0.0
        repeat {
            // Create new centers every loop
            var centerCandidates = [Pixel](repeating: Pixel(r: 0, g: 0, b: 0, a: 0), count: partitions)
            var totals = [Int](repeating: 0, count: partitions)
            
            // Calculate nearest points to centers
            for pixel in entries {
                // Update data points
                let index = indexOfNearestCentroid(pixel, centroids: centroids)
                centerCandidates[index].append(pixel)
                totals[index] += 1
            }
            
            // Average out data
            for i in 0..<partitions {
                centerCandidates[i].averageOut(count: totals[i])
            }
            
            // Calculate how much each centroid moved
            centerMoveDist = 0.0
            for i in 0..<partitions {
                centerMoveDist += centroids[i].distanceTo(centerCandidates[i])
            }
            
            // Set new centroids
            centroids = centerCandidates
        } while centerMoveDist > tolerance
        
        return centroids
    }
    
    func calculateProminentClusters() -> [Pixel] {
        // Get pixels
        let pixels = kMeans(partitions: clusterNumber, tolerance: tolerance, entries: dataPoints)
        
        // Sort by count
        return pixels.sorted {
            $0.count > $1.count
        }
    }
}
