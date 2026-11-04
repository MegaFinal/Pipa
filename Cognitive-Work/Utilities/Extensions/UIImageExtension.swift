//
//  UIImageExtention.swift
//  Cognitive-Work
//
//  Created by Isabela Hissa Pinto on 28/08/26.
//

import UIKit

extension UIImage {
    
    // MARK: - E-Paper Image Preparation (Black and White)

    /// The levelBitmap function takes an image, scales it to fit the screen, creates a source buffer
    /// with that scaled image in RGBA (32 bits per pixel) and uses that buffer to create a
    /// second destination buffer with only BW (1 bit per pixel) by checking the lightness of each pixel of the
    /// source buffer.
    ///
    /// A bitmap (or bit map) is a matrix of dots that defines the color of each pixel in a digital image.
    ///
    /// - Parameters:
    ///   - image: The image to be converted to the panel's format.
    /// - Returns: Main function that returns the Data object of 48,000 bytes (black plane only).
    func levelBitmap() -> Data? {

        // ------------------------------------- Setup variables -------------------------------------
        
        let ePaperWidth = 800  // GDEY075T7 7.5"
        let ePaperHeight = 480

        // The panel uses 1 bit per pixel (only black or white, no intermediate tones).
        // 800 × 480 = 384,000 pixels ÷ 8 bits per byte = 48,000 bytes.
        let bytesPerLayer = (ePaperWidth * ePaperHeight) / 8

        // Color space of the bitmap, in this case, indicates that it has three (R G B)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        // flags for the context =  1  |  16384  →  16385
        // premultipliedLast adds a fourth channel, the alpha (transparency) as the last byte of the 4 bytes.
        // Each byte represents a color in a pixel (R G B A).
        // It also describes that the R G B bytes have already been multiplied beforehand by the A, so it no longer exerts any influence.
        // byteOrder32Big prevents the inversion of the pixels' bytes (keeps R G B A)
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

        // CGContext: Allocates the bitmap's bytes
        // data: you can pass your own pointer or let Core Graphics allocate and deallocate
        // bitsPerComponent: number of bits per channel (one color). 8 = 0 - 255
        // bytesPerRow: number of bytes per row, so it knows where to jump to reach the next one
        // space: colorSpace, bitmapInfo: bitmapInfo -> descriptions of the bitmap
        guard let context = CGContext(data: nil, width: ePaperWidth, height: ePaperHeight,
                                      bitsPerComponent: 8, bytesPerRow: ePaperWidth * 4,
                                      space: colorSpace, bitmapInfo: bitmapInfo) else {
            return nil
        }

        // CGBitmapContext has its origin at the bottom-left corner. Y grows upward.
        // UIKit has its origin at the top-left corner. Y grows downward.
        // Below: Converts to UIKit's coordinate system (origin at the top-left)
        context.translateBy(x: 0, y: CGFloat(ePaperHeight))
        context.scaleBy(x: 1, y: -1)

        // Updates (pushes) UIKit's context to the newly created one -> any new drawing uses this context
        UIGraphicsPushContext(context)

        // ------------------------------------- Fills the source buffer -------------------------------------
        // Each pixel has 32 bits (4 bytes)

        // Chooses the color to be filled in the context
        UIColor.white.setFill()
        // Fills a rectangle with the color (so the background isn't left transparent)
        UIRectFill(CGRect(x: 0, y: 0, width: ePaperWidth, height: ePaperHeight))

        // Chooses the smallest ratio from the proportions between the frame and the image
        let aspectWidth = CGFloat(ePaperWidth) / self.size.width
        let aspectHeight = CGFloat(ePaperHeight) / self.size.height
        let ratio = min(aspectWidth, aspectHeight)

        // New height and width based on the ratio
        let newWidth = self.size.width * ratio
        let newHeight = self.size.height * ratio

        // Centers the image
        let xOffset = (CGFloat(ePaperWidth) - newWidth) / 2.0
        let yOffset = (CGFloat(ePaperHeight) - newHeight) / 2.0

        // Draws the image with the new dimensions at the x and y determined to center it
        self.draw(in: CGRect(x: xOffset, y: yOffset, width: newWidth, height: newHeight))

        // Pops UIKit's context
        UIGraphicsPopContext()

        // Pointer to the buffer allocated by Core Graphics, comes as type UnsafeMutableRawPointer (void*)
        guard let pixelBuffer = context.data else { return nil }
        // cast of the pointer to UInt8 (Unsigned Integer of 8 bits)
        // 1 byte (8 bits) 0 - 255 | [R][G][B][A]  ← each one is a UInt8
        let data = pixelBuffer.bindMemory(to: UInt8.self, capacity: ePaperWidth * ePaperHeight * 4)

        // ------------------------------------- Creates the destination buffer -------------------------------------
        // Each pixel has one bit

        // Creates a new buffer that will receive the BW image. Array of 48,000 zeroed bytes
        var blackBuffer = [UInt8](repeating: 0, count: bytesPerLayer)

        // Walks through the source byte matrix, going over every pixel
        for y in 0..<ePaperHeight {
            for x in 0..<ePaperWidth {

                // Finds the pixel's index by multiplying by the row and by 4 since each pixel has 4 bytes + col * 4
                let pixelIndex = (y * ePaperWidth * 4) + (x * 4)

                // Receives the value of each color and ignores the alpha
                let r = Int(data[pixelIndex])
                let g = Int(data[pixelIndex + 1])
                let b = Int(data[pixelIndex + 2])

                // Calculates whether it is light or dark
                // ITU-R BT.601 luma. The weights are unequal because the eye is much more sensitive to green than to blue.
                // 299+587+114 sums to 1000, so dividing by 1000 gives back the 0–255 scale.
                let brightness = (r * 299 + g * 587 + b * 114) / 1000

                // Bool for whether it is light or not
                let isWhite = brightness > 160
                // Inserts 0 into the buffer if it is light or 1 if it is dark
                let bitColor: UInt8 = isWhite ? 0 : 1

                // Calculation of the destination buffer's index: divides by 8 since each pixel is now a bit,
                // but the notation is in bytes -> truncated return
                let byteIndex = (y * (ePaperWidth / 8)) + (x / 8)

                // Finds the bit's position inside the byteIndex
                // In this case it finds the "complement", since bytes are read from right to left
                let bitPosition = 7 - (x % 8)

                // Writing the bit into the byte
                // in the array at the byte in question, pushes (<<) the color that is in bitColor (0 or 1)
                // to the bitPosition position. The |= does an overlay (OR)
                blackBuffer[byteIndex] |= (bitColor << bitPosition)
            }
        }

        return Data(blackBuffer) // Returns exactly 48,000 bytes
    }
    
    
    
    // MARK: - E-Paper Image Preparation with Dithering

    /// The ditheringBitmap function does the same job as levelBitmap — it turns a UIImage into
    /// the 1 bit per pixel buffer the panel expects — but instead of deciding each pixel in isolation,
    /// it applies Floyd-Steinberg error diffusion.
    ///
    /// A plain threshold throws away everything between black and white, so gradients turn into flat
    /// blotches. Error diffusion carries the rounding error of each pixel over to its neighbours, so a
    /// mid-gray area becomes a mix of black and white dots whose density reads as gray from a distance.
    ///
    /// - Parameters:
    ///   - image: The image to be converted to the panel's format.
    /// - Returns: The Data object of 48,000 bytes (black plane only).
    func ditheringBitmap() -> Data? {

        // ------------------------------------- Setup variables -------------------------------------
        // Identical to levelBitmap — see that function for the details.

        let ePaperWidth = 800
        let ePaperHeight = 480
        let bytesPerLayer = (ePaperWidth * ePaperHeight) / 8

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let context = CGContext(data: nil, width: ePaperWidth, height: ePaperHeight,
                                      bitsPerComponent: 8, bytesPerRow: ePaperWidth * 4,
                                      space: colorSpace, bitmapInfo: bitmapInfo) else {
            return nil
        }

        context.translateBy(x: 0, y: CGFloat(ePaperHeight))
        context.scaleBy(x: 1, y: -1)

        UIGraphicsPushContext(context)
        UIColor.white.setFill()
        UIRectFill(CGRect(x: 0, y: 0, width: ePaperWidth, height: ePaperHeight))

        // Chooses the smallest ratio from the proportions between the frame and the image
        let aspectWidth = CGFloat(ePaperWidth) / self.size.width
        let aspectHeight = CGFloat(ePaperHeight) / self.size.height
        let ratio = min(aspectWidth, aspectHeight)

        // New height and width based on the ratio
        let newWidth = self.size.width * ratio
        let newHeight = self.size.height * ratio

        // Centers the image
        let xOffset = (CGFloat(ePaperWidth) - newWidth) / 2.0
        let yOffset = (CGFloat(ePaperHeight) - newHeight) / 2.0

        // Draws the image with the new dimensions at the x and y determined to center it
        self.draw(in: CGRect(x: xOffset, y: yOffset, width: newWidth, height: newHeight))
        UIGraphicsPopContext()

        guard let pixelBuffer = context.data else { return nil }
        let data = pixelBuffer.bindMemory(to: UInt8.self, capacity: ePaperWidth * ePaperHeight * 4)

        // ------------------------------------- Grayscale pass -------------------------------------
        // DIFFERENT: levelBitmap computes the brightness and decides the bit in the same step.
        // Here the brightness of every pixel is stored first, because error diffusion needs to go back
        // and modify neighbours that haven't been visited yet.
        // Float instead of Int because the accumulated error can push a value past 255 or below 0.

        var gray = [Float](repeating: 0, count: ePaperWidth * ePaperHeight)
        for y in 0..<ePaperHeight {
            for x in 0..<ePaperWidth {
                // One entry per pixel here, against 4 bytes per pixel in the source buffer
                let grayIndex = y * ePaperWidth + x
                let pixelIndex = grayIndex * 4

                let r = Float(data[pixelIndex])
                let g = Float(data[pixelIndex + 1])
                let b = Float(data[pixelIndex + 2])

                // Same ITU-R BT.601 luma, written as fractions instead of the /1000 integer form
                let brightness = r * 0.299 + g * 0.587 + b * 0.114
                gray[grayIndex] = brightness
            }
        }

        var blackBuffer = [UInt8](repeating: 0, count: bytesPerLayer)

        // ------------------------------------- Floyd-Steinberg -------------------------------------
        // Creates the illusion of gray through the density of black pixels.

        for y in 0..<ePaperHeight {
            for x in 0..<ePaperWidth {
                let grayIndex = y * ePaperWidth + x

                // The value read here already carries the error pushed by the pixels visited before it
                let oldPixel = gray[grayIndex]
                let isWhite = oldPixel > 128
                let newPixel: Float = isWhite ? 255 : 0

                // How much brightness was lost by rounding to pure black or pure white.
                // Positive means the pixel was darkened too much, negative the opposite.
                let error = oldPixel - newPixel

                // DIFFERENT: spreads the error over the neighbours that haven't been decided yet,
                // using the Floyd-Steinberg kernel:
                //
                //           X    7/16
                //    3/16  5/16  1/16
                //
                // The bounds checks stop the error from wrapping around the edges of the image.
                if x + 1 < ePaperWidth {
                    gray[grayIndex + 1] += error * 7.0 / 16.0
                }
                if y + 1 < ePaperHeight {
                    if x > 0 {
                        gray[grayIndex + ePaperWidth - 1] += error * 3.0 / 16.0
                    }
                    gray[grayIndex + ePaperWidth] += error * 5.0 / 16.0
                    if x + 1 < ePaperWidth {
                        gray[grayIndex + ePaperWidth + 1] += error * 1.0 / 16.0
                    }
                }

                // DIFFERENT: only writes when the pixel is dark, instead of OR-ing a bitColor that
                // would be 0 anyway. Same result — the buffer starts zeroed, so white is a no-op.
                if !isWhite {
                    let byteIndex = (y * (ePaperWidth / 8)) + (x / 8)
                    let bitPosition = 7 - (x % 8)
                    blackBuffer[byteIndex] |= (1 << bitPosition)
                }
            }
        }

        return Data(blackBuffer)
    }
    
    
    
    // MARK: - E-Paper Image Preparation (4 Grayscale Levels)

    /// The levelBitmap4Gray function turns a UIImage into the 2 bits per pixel buffer that a
    /// 4-grayscale e-paper panel expects. Unlike levelBitmap (1 bit: black or white) and
    /// ditheringBitmap (1 bit with error diffusion), here each pixel keeps one of FOUR real tones:
    /// black, dark gray, light gray and white.
    ///
    /// 2 bits per pixel means 4 pixels fit in each byte, so the buffer is (width × height) / 4 bytes.
    ///
    /// - Parameter halfTones: When `true`, also shows the three tones *between* the four levels
    ///   (see ``eInkHalfTones``) as a checkerboard of the two neighbouring levels, which the eye
    ///   reads as the shade in between: 7 tones instead of 4. Done here, on the final pixel grid,
    ///   because a pattern drawn in SwiftUI can land half a pixel off and blend into one gray.
    /// - Returns: The Data object of 96,000 bytes.
    func levelBitmap4Gray(halfTones: Bool = false) -> Data? {

        // ------------------------------------- Setup variables -------------------------------------
        // Same source-buffer setup as levelBitmap — see that function for the details.

        let ePaperWidth = 800   // GDEY075T7 7.5"
        let ePaperHeight = 480

        // 2 bits per pixel now: 4 pixels per byte.
        // 800 × 480 = 384,000 pixels ÷ 4 pixels per byte = 96,000 bytes.
        let bytesTotal = (ePaperWidth * ePaperHeight) / 4

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

        guard let context = CGContext(data: nil, width: ePaperWidth, height: ePaperHeight,
                                      bitsPerComponent: 8, bytesPerRow: ePaperWidth * 4,
                                      space: colorSpace, bitmapInfo: bitmapInfo) else {
            return nil
        }

        context.translateBy(x: 0, y: CGFloat(ePaperHeight))
        context.scaleBy(x: 1, y: -1)

        UIGraphicsPushContext(context)
        UIColor.white.setFill()
        UIRectFill(CGRect(x: 0, y: 0, width: ePaperWidth, height: ePaperHeight))

        // Centers the image keeping aspect ratio (same as the other functions)
        let aspectWidth = CGFloat(ePaperWidth) / self.size.width
        let aspectHeight = CGFloat(ePaperHeight) / self.size.height
        let ratio = min(aspectWidth, aspectHeight)
        let newWidth = self.size.width * ratio
        let newHeight = self.size.height * ratio
        let xOffset = (CGFloat(ePaperWidth) - newWidth) / 2.0
        let yOffset = (CGFloat(ePaperHeight) - newHeight) / 2.0
        self.draw(in: CGRect(x: xOffset, y: yOffset, width: newWidth, height: newHeight))

        UIGraphicsPopContext()

        guard let pixelBuffer = context.data else { return nil }
        let data = pixelBuffer.bindMemory(to: UInt8.self, capacity: ePaperWidth * ePaperHeight * 4)

        // ------------------------------------- Creates the destination buffer -------------------------------------
        // Each pixel now takes 2 bits. The buffer starts zeroed.

        var grayBuffer = [UInt8](repeating: 0, count: bytesTotal)

        // Half-tone mode: for each brightness, the level of the even and of the odd pixels.
        let halfToneTable: [(even: UInt8, odd: UInt8)] = halfTones
            ? (0...255).map { UIImage.halfToneLevels(forBrightness: $0) }
            : []

        for y in 0..<ePaperHeight {
            for x in 0..<ePaperWidth {

                let pixelIndex = (y * ePaperWidth * 4) + (x * 4)

                let r = Int(data[pixelIndex])
                let g = Int(data[pixelIndex + 1])
                let b = Int(data[pixelIndex + 2])

                // Same ITU-R BT.601 luma as levelBitmap: 0 (black) .. 255 (white)
                let brightness = (r * 299 + g * 587 + b * 114) / 1000

                // DIFFERENT: instead of one threshold, split the 0–255 range into 4 bands.
                // Maps brightness to a 2-bit value:
                //   0 = black, 1 = dark gray, 2 = light gray, 3 = white
                let level: UInt8
                if halfTones {
                    let levels = halfToneTable[brightness]
                    level = (x + y) & 1 == 0 ? levels.even : levels.odd
                } else if brightness < 64 {
                    level = 0            // black
                } else if brightness < 128 {
                    level = 1            // dark gray
                } else if brightness < 192 {
                    level = 2            // light gray
                } else {
                    level = 3            // white
                }

                // DIFFERENT: 4 pixels per byte instead of 8.
                // byteIndex divides x by 4 (not 8) since each pixel is 2 bits.
                let byteIndex = (y * (ePaperWidth / 4)) + (x / 4)

                // Which of the 4 slots inside the byte (0..3), read left to right.
                // Each slot is 2 bits, so we shift by 6, 4, 2, 0.
                let slot = x % 4
                let bitShift = 6 - (slot * 2)

                // Writes the 2-bit level into its slot with OR (buffer starts zeroed).
                grayBuffer[byteIndex] |= (level << bitShift)
            }
        }

        return Data(grayBuffer)   // 96,000 bytes
    }

    /// The 7 tones ``levelBitmap4Gray(halfTones:)`` can show: the brightness a view should paint
    /// (0–255) and the 2-bit levels used on even and odd pixels (0 black … 3 white). Equal levels
    /// are the panel's own tones; different ones are the checkerboard tones between them.
    static let eInkHalfTones: [(brightness: Int, even: UInt8, odd: UInt8)] = [
        (0, 0, 0),      // black
        (48, 0, 1),     // black / dark gray
        (96, 1, 1),     // dark gray
        (128, 1, 2),    // dark gray / light gray
        (160, 2, 2),    // light gray
        (208, 2, 3),    // light gray / white
        (255, 3, 3),    // white
    ]

    /// The tone nearest to `brightness`, as the levels of its even and odd pixels.
    private static func halfToneLevels(forBrightness brightness: Int) -> (even: UInt8, odd: UInt8) {
        let tone = eInkHalfTones.min { abs($0.brightness - brightness) < abs($1.brightness - brightness) }!
        return (tone.even, tone.odd)
    }
}
