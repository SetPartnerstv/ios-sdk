//
//  QRBarcodeGenerator.swift
//
//  Created by Nikolay Kapustin on 08.09.2025.
//  Copyright © 2025. All rights reserved.
//

import Foundation
import CoreImage.CIFilterBuiltins
import UIKit

public enum QRBarCodeType: Int, CaseIterable {
    case unspecified = 0
    case qr
    case barcodeEAN13
    case barcodeEAN8
    case barcodeEAN128
}

public struct QRBarCodeGenerator {
    public static func generateImage(type: QRBarCodeType,
                                     for value: String,
                                     quietSpace: CGFloat = 20) -> UIImage? {

        guard value.count > 0 else { return nil }

        let filter:CIFilter?
        var desiredSize: CGSize = CGSize(width: 650, height: 180)
        switch type {
        case .qr:
            filter = CIFilter(name: "CIQRCodeGenerator")
            filter?.setValue("M", forKey: "inputCorrectionLevel")
            desiredSize = CGSize(width: 200, height: 200)
            filter?.setValue(value.data(using: .utf8), forKey: "inputMessage")
            break
        case .barcodeEAN13, .barcodeEAN8:
            desiredSize = CGSize(width: 550, height: 180)
            filter = CIFilter(name: "CIEANBarcodeGenerator")
            filter?.setValue(value, forKey: "inputMessage")
            break
        case .barcodeEAN128:
            filter = CIFilter(name: "CICode128BarcodeGenerator")
            filter?.setValue(value.data(using: .ascii), forKey: "inputMessage")
            break
        default:
            return nil
        }
        guard let image = filter?.outputImage, let result = letterboxCIImage(image, into: desiredSize)
        else {
            return nil
        }
        return UIImage(ciImage: result)
    }

    /// Letterboxing image to desired size.
    static func letterboxCIImage(_ input: CIImage,
                          into targetSize: CGSize) -> CIImage? {
        // Some initial's checks
        let inputExtentWidth = input.extent.width
        let inputExtentHeight = input.extent.height
        guard inputExtentWidth > 0, inputExtentHeight > 0, targetSize.width > 0, targetSize.height > 0 else { return nil }

        // Calculate a scale factor'a to boxing input image
        let scaleFactor = min(targetSize.width / inputExtentWidth, targetSize.height / inputExtentHeight)
        let scaleFactorDecreaseToBoxing: CGFloat = 0.9

        // Firest, decrease scale barcode
        var scaledModificiedInput = input.transformed(by: CGAffineTransform(scaleX: scaleFactor * scaleFactorDecreaseToBoxing,
                                                                           y: scaleFactor * scaleFactorDecreaseToBoxing))
        let scaledExtent = scaledModificiedInput.extent
        // Calculate a tranform to move barcode at center (letterboxing)
        let dx = (targetSize.width  - scaledExtent.width)  * 0.5 - scaledExtent.origin.x
        let dy = (targetSize.height - scaledExtent.height) * 0.5 - scaledExtent.origin.y
        scaledModificiedInput = scaledModificiedInput.transformed(by: CGAffineTransform(translationX: dx, y: dy))

        // A compositing filter put the barcode over a white background (in fact combining)
        let filter = CIFilter.sourceOverCompositing()
        filter.inputImage = scaledModificiedInput
        filter.backgroundImage = CIImage(color: CIColor.white)
        guard let result = filter.outputImage else { return nil }

        // Clamping to target size
        return result.cropped(to: CGRect(origin: .zero, size: targetSize))
    }
}
