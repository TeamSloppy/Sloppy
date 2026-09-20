import AdaEngine
import Math

struct NotchPetTextures: Resource {
    let body = Texture2D(image: NotchPetTextureFactory.makeBody(width: 100, height: 116))
    let ellipse = Texture2D(image: NotchPetTextureFactory.makeEllipse(width: 64, height: 64))
    let capsule = Texture2D(image: NotchPetTextureFactory.makeCapsule(width: 24, height: 58))
}

private enum NotchPetTextureFactory {
    static func makeBody(width: Int, height: Int) -> Image {
        var image = Image(width: width, height: height)
        let center = Vector2(Float(width) / 2, Float(height) * 0.53)
        let radii = Vector2(Float(width) * 0.43, Float(height) * 0.43)

        for y in 0..<height {
            for x in 0..<width {
                let point = Vector2(Float(x) + 0.5, Float(y) + 0.5)
                let normalized = (point - center) / radii
                var signedDistance = normalized.squaredLength.squareRoot() - 1

                let lowerBulgeCenter = Vector2(center.x + 3, center.y - 28)
                let lowerNormalized = (point - lowerBulgeCenter) / Vector2(40, 30)
                signedDistance = min(signedDistance, lowerNormalized.squaredLength.squareRoot() - 1)

                let alpha = smoothAlpha(signedDistance, softness: 0.032)
                let highlightVector = (point - Vector2(center.x - 16, center.y + 22)) / Vector2(45, 58)
                let highlight = max(0, 1 - highlightVector.squaredLength.squareRoot())
                let shade = max(0, min(1, (Float(y) / Float(height)) * 0.11 + highlight * 0.045))
                image.setPixel(
                    in: Point(x: Float(x), y: Float(y)),
                    color: Color(
                        red: 0.87 + shade,
                        green: 0.88 + shade,
                        blue: 0.90 + shade,
                        alpha: alpha
                    )
                )
            }
        }
        return image
    }

    static func makeEllipse(width: Int, height: Int) -> Image {
        var image = Image(width: width, height: height)
        let center = Vector2(Float(width) / 2, Float(height) / 2)
        let radii = Vector2(Float(width) / 2 - 1, Float(height) / 2 - 1)
        for y in 0..<height {
            for x in 0..<width {
                let point = Vector2(Float(x) + 0.5, Float(y) + 0.5)
                let distance = ((point - center) / radii).squaredLength.squareRoot() - 1
                image.setPixel(
                    in: Point(x: Float(x), y: Float(y)),
                    color: Color(red: 1, green: 1, blue: 1, alpha: smoothAlpha(distance, softness: 0.055))
                )
            }
        }
        return image
    }

    static func makeCapsule(width: Int, height: Int) -> Image {
        var image = Image(width: width, height: height)
        let centerX = Float(width) / 2
        let radius = Float(width) / 2 - 1
        let lowerCenter = Vector2(centerX, radius + 1)
        let upperCenter = Vector2(centerX, Float(height) - radius - 1)

        for y in 0..<height {
            for x in 0..<width {
                let point = Vector2(Float(x) + 0.5, Float(y) + 0.5)
                let closestY = max(lowerCenter.y, min(upperCenter.y, point.y))
                let distance = (point - Vector2(centerX, closestY)).squaredLength.squareRoot() - radius
                let alpha = max(0, min(1, 1 - distance))
                image.setPixel(
                    in: Point(x: Float(x), y: Float(y)),
                    color: Color(red: 1, green: 1, blue: 1, alpha: alpha)
                )
            }
        }
        return image
    }

    private static func smoothAlpha(_ signedDistance: Float, softness: Float) -> Float {
        max(0, min(1, 0.5 - signedDistance / softness))
    }
}
