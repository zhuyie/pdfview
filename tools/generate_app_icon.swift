#!/usr/bin/env swift

import AppKit
import Foundation

func makeColor(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1.0) -> NSColor {
    NSColor(calibratedRed: red / 255.0, green: green / 255.0, blue: blue / 255.0, alpha: alpha)
}

func drawRoundedRect(_ rect: NSRect, radius: CGFloat, color: NSColor) {
    color.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    guard let context = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    context.interpolationQuality = .high

    let canvas = NSRect(x: 0, y: 0, width: size, height: size)
    let outerPath = NSBezierPath(roundedRect: canvas.insetBy(dx: size * 0.04, dy: size * 0.04),
                                 xRadius: size * 0.22,
                                 yRadius: size * 0.22)
    outerPath.addClip()

    let gradient = NSGradient(colors: [
        makeColor(255, 187, 92),
        makeColor(243, 127, 87),
        makeColor(236, 87, 90)
    ])!
    gradient.draw(in: canvas, angle: -45.0)

    makeColor(255, 255, 255, 0.12).setFill()
    NSBezierPath(ovalIn: NSRect(x: size * 0.02, y: size * 0.56, width: size * 0.84, height: size * 0.46)).fill()

    let shadow = NSShadow()
    shadow.shadowBlurRadius = size * 0.03
    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.02)
    shadow.shadowColor = makeColor(24, 18, 27, 0.24)
    shadow.set()

    let paperRect = NSRect(x: size * 0.20, y: size * 0.15, width: size * 0.53, height: size * 0.66)
    drawRoundedRect(paperRect, radius: size * 0.08, color: makeColor(252, 249, 244))
    NSShadow().set()

    drawRoundedRect(NSRect(x: size * 0.23,
                           y: size * 0.19,
                           width: size * 0.08,
                           height: size * 0.58),
                    radius: size * 0.03,
                    color: makeColor(229, 84, 74))

    drawRoundedRect(NSRect(x: size * 0.34,
                           y: size * 0.67,
                           width: size * 0.28,
                           height: size * 0.05),
                    radius: size * 0.018,
                    color: makeColor(246, 192, 112))

    for index in 0..<3 {
        drawRoundedRect(NSRect(x: size * 0.34,
                               y: size * (0.56 - CGFloat(index) * 0.11),
                               width: size * (0.28 - CGFloat(index) * 0.03),
                               height: size * 0.035),
                        radius: size * 0.015,
                        color: makeColor(219, 212, 225))
    }

    let foldPath = NSBezierPath()
    foldPath.move(to: NSPoint(x: size * 0.60, y: size * 0.81))
    foldPath.line(to: NSPoint(x: size * 0.73, y: size * 0.81))
    foldPath.line(to: NSPoint(x: size * 0.73, y: size * 0.68))
    foldPath.close()
    makeColor(241, 233, 224).setFill()
    foldPath.fill()

    let lensCenter = NSPoint(x: size * 0.67, y: size * 0.33)
    let lensShadow = NSShadow()
    lensShadow.shadowBlurRadius = size * 0.025
    lensShadow.shadowOffset = NSSize(width: 0, height: -size * 0.012)
    lensShadow.shadowColor = makeColor(18, 28, 43, 0.32)
    lensShadow.set()

    let lensRect = NSRect(x: lensCenter.x - size * 0.17,
                          y: lensCenter.y - size * 0.17,
                          width: size * 0.34,
                          height: size * 0.34)
    drawRoundedRect(lensRect, radius: size * 0.17, color: makeColor(21, 40, 61))
    NSShadow().set()

    let ringRect = NSRect(x: lensCenter.x - size * 0.11,
                          y: lensCenter.y - size * 0.11,
                          width: size * 0.22,
                          height: size * 0.22)
    let ringPath = NSBezierPath(ovalIn: ringRect)
    ringPath.lineWidth = size * 0.035
    makeColor(255, 255, 255).setStroke()
    ringPath.stroke()

    let handle = NSBezierPath(roundedRect: NSRect(x: size * 0.74,
                                                  y: size * 0.18,
                                                  width: size * 0.055,
                                                  height: size * 0.18),
                              xRadius: size * 0.02,
                              yRadius: size * 0.02)
    var transform = AffineTransform()
    transform.translate(x: size * 0.767, y: size * 0.27)
    transform.rotate(byDegrees: -43.0)
    transform.translate(x: -size * 0.767, y: -size * 0.27)
    handle.transform(using: transform)
    makeColor(255, 255, 255).setFill()
    handle.fill()

    image.unlockFocus()
    return image
}

func writePNG(image: NSImage, to url: URL) throws {
    guard
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let png = bitmap.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "pdfview.icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode PNG"])
    }
    try png.write(to: url)
}

func main() throws {
    guard CommandLine.arguments.count == 2 else {
        fputs("usage: generate_app_icon.swift <output.icns>\n", stderr)
        exit(1)
    }

    let outputURL = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
    try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)

    let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
    let iconsetURL = tempRoot.appendingPathComponent("pdfview.iconset")
    try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

    let sizes: [(CGFloat, String)] = [
        (16, "icon_16x16.png"),
        (32, "icon_16x16@2x.png"),
        (32, "icon_32x32.png"),
        (64, "icon_32x32@2x.png"),
        (128, "icon_128x128.png"),
        (256, "icon_128x128@2x.png"),
        (256, "icon_256x256.png"),
        (512, "icon_256x256@2x.png"),
        (512, "icon_512x512.png"),
        (1024, "icon_512x512@2x.png"),
    ]

    for (size, name) in sizes {
        try writePNG(image: drawIcon(size: size), to: iconsetURL.appendingPathComponent(name))
    }

    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    task.arguments = ["-c", "icns", iconsetURL.path, "-o", outputURL.path]
    try task.run()
    task.waitUntilExit()
    if task.terminationStatus != 0 {
        throw NSError(domain: "pdfview.icon", code: Int(task.terminationStatus),
                      userInfo: [NSLocalizedDescriptionKey: "iconutil failed"])
    }

    try? FileManager.default.removeItem(at: tempRoot)
}

do {
    try main()
} catch {
    fputs("\(error)\n", stderr)
    exit(1)
}
