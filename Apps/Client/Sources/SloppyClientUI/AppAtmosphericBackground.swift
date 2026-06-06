import AdaEngine
import Foundation

public struct AppAtmosphericBackground: View {
    @Environment(\.theme) private var theme
    @Environment(\.accentColor) private var accentColor

    public init() {}

    public var body: some View {
        let c = theme.colors

        return ZStack(anchor: .bottom) {
            c.background
                .ignoresSafeArea()

            // // Keep the expensive full-screen atmospheric layer static. The only
            // // animated part is the much smaller bottom wave below, so the app keeps
            // // the requested pulse without putting the whole scene back into a
            // // continuous full-screen redraw loop.
            // Color.clear
            //     .shaderEffect(
            //         CustomMaterial(
            //             AppAtmosphericBackgroundMaterial(
            //                 time: 0,
            //                 accentColor: accentColor
            //             )
            //         ),
            //         placement: .overlay
            //     )
            //     .frame(maxWidth: .infinity, maxHeight: .infinity)
            //     .allowsHitTesting(false)
            //     .ignoresSafeArea()

            // TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            //     let animatedTime = Float(
            //         context.date.timeIntervalSinceReferenceDate
            //             .truncatingRemainder(dividingBy: 4096)
            //     )

            //     Color.clear
            //         .shaderEffect(
            //             CustomMaterial(
            //                 AppBottomWaveMaterial(
            //                     time: animatedTime,
            //                     accentColor: accentColor
            //                 )
            //             ),
            //             placement: .overlay
            //         )
            //         .frame(maxWidth: .infinity, maxHeight: 190)
            //         .allowsHitTesting(false)
            // }
            // .ignoresSafeArea()
        }
        .ignoresSafeArea()
    }
}

private struct AppAtmosphericBackgroundMaterial: UIShaderMaterial {
    @Uniform(binding: 0, propertyName: "u_Time")
    var time: Float

    @Uniform(binding: 0, propertyName: "u_AccentColor")
    var accentColor: Color

    init(time: Float, accentColor: Color) {
        self.time = time
        self.accentColor = accentColor
    }

    static func fragmentShader() throws -> AssetHandle<ShaderSource> {
        let source = """
            #version 450 core
            #pragma stage : frag

            #include <AdaEngine/UIShaderMaterial.frag>

            layout (binding = 0) uniform AppAtmosphericBackgroundMaterial {
                float u_Time;
                vec4 u_AccentColor;
            };

            float hash(vec2 p)
            {
                p = fract(p * vec2(123.34, 456.21));
                p += dot(p, p + 45.32);
                return fract(p.x * p.y);
            }

            float valueNoise(vec2 p)
            {
                vec2 i = floor(p);
                vec2 f = fract(p);
                vec2 u = f * f * (3.0 - 2.0 * f);

                float a = hash(i);
                float b = hash(i + vec2(1.0, 0.0));
                float c = hash(i + vec2(0.0, 1.0));
                float d = hash(i + vec2(1.0, 1.0));

                return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
            }

            float fbm(vec2 p)
            {
                float v = 0.0;
                float amplitude = 0.5;

                for (int i = 0; i < 4; i++) {
                    v += valueNoise(p) * amplitude;
                    p = p * 2.03 + vec2(7.1, 3.7);
                    amplitude *= 0.5;
                }

                return v;
            }

            [[main]]
            void app_atmospheric_background_fragment()
            {
                vec2 uv = Input.UV;
                float bottom = 1.0 - uv.y;

                // Limit the effect to the lower part of the screen, with a soft fade up.
                float baseFade = smoothstep(0.0, 0.68, bottom);
                baseFade = baseFade * baseFade;

                // Gentle breathing pulse.
                float pulse = 0.86 + 0.14 * sin(u_Time * 1.15);

                // Aurora-like horizontal shimmer bands drifting at different speeds.
                float y = bottom;
                float wave1 = sin((uv.x * 3.2 + y * 2.7) * 6.28318 + u_Time * 0.72);
                float wave2 = sin((uv.x * 5.4 - y * 1.8) * 6.28318 - u_Time * 0.43);
                float wave3 = sin((uv.x * 1.6 + y * 5.2) * 6.28318 + u_Time * 0.31);
                float waves = wave1 * 0.34 + wave2 * 0.24 + wave3 * 0.18;

                float noise = fbm(vec2(uv.x * 2.8, y * 2.2) + vec2(u_Time * 0.045, -u_Time * 0.025));
                float shimmer = 0.70 + 0.30 * smoothstep(0.18, 0.92, noise + waves * 0.28);

                // A few soft moving highlight layers, but no spherical blobs.
                float bandA = exp(-pow((y - (0.30 + 0.045 * sin(u_Time * 0.52 + uv.x * 5.0))) / 0.145, 2.0));
                float bandB = exp(-pow((y - (0.47 + 0.035 * sin(u_Time * 0.38 - uv.x * 4.0))) / 0.175, 2.0));
                float bands = bandA * 0.16 + bandB * 0.11;

                float bottomBloom = smoothstep(0.22, 1.0, bottom) * 0.20;
                float alpha = (baseFade * (0.27 * shimmer + bands) + bottomBloom) * pulse;
                alpha = clamp(alpha, 0.0, 0.48);

                // Slightly lift the color in highlights while keeping it based on accentColor.
                vec3 highlight = mix(u_AccentColor.rgb, vec3(0.78, 0.93, 1.0), 0.22 * shimmer);
                COLOR = vec4(highlight, alpha * u_AccentColor.a);
            }
            """

        return AssetHandle(try ShaderSource(source: source))
    }
}

private struct AppBottomWaveMaterial: UIShaderMaterial {
    @Uniform(binding: 0, propertyName: "u_Time")
    var time: Float

    @Uniform(binding: 0, propertyName: "u_AccentColor")
    var accentColor: Color

    init(time: Float, accentColor: Color) {
        self.time = time
        self.accentColor = accentColor
    }

    static func fragmentShader() throws -> AssetHandle<ShaderSource> {
        let source = """
            #version 450 core
            #pragma stage : frag

            #include <AdaEngine/UIShaderMaterial.frag>

            layout (binding = 0) uniform AppBottomWaveMaterial {
                float u_Time;
                vec4 u_AccentColor;
            };

            [[main]]
            void app_bottom_wave_fragment()
            {
                vec2 uv = Input.UV;
                float t = u_Time;

                // The view itself is only ~190pt tall and anchored to the bottom.
                // Build a clearly visible lower wave silhouette whose crest moves and
                // breathes. Keep the math cheap: a few sine waves + smoothstep, no FBM.
                float bottom = 1.0 - uv.y;
                float crest = 0.46
                    + 0.085 * sin((uv.x * 1.35 + t * 0.145) * 6.28318)
                    + 0.040 * sin((uv.x * 2.75 - t * 0.105) * 6.28318)
                    + 0.020 * sin((uv.x * 5.20 + t * 0.070) * 6.28318);

                float pulse = 0.84 + 0.16 * sin(t * 1.55);

                // `smoothstep(a, b, x)` is only well-defined for a < b. The previous
                // shader used reversed edges, which can collapse the wave to nearly
                // invisible depending on the graphics backend. This keeps the body on
                // the screen-bottom side of the crest and fades it upward.
                float body = smoothstep(crest - 0.065, crest + 0.115, bottom);
                float edge = 1.0 - smoothstep(0.0, 0.075, abs(bottom - crest));
                float verticalFade = smoothstep(0.0, 0.24, bottom);

                float ripple = 0.62 + 0.38 * sin((uv.x * 2.35 + bottom * 1.7 - t * 0.20) * 6.28318);
                float lowerGlow = smoothstep(0.58, 1.0, bottom) * 0.20;
                float alpha = ((body * 0.38) + (edge * 0.30 * ripple) + lowerGlow) * verticalFade * pulse;
                alpha = clamp(alpha, 0.0, 0.66);

                vec3 waveColor = mix(u_AccentColor.rgb, vec3(0.72, 0.92, 1.0), 0.34 + edge * 0.22);
                COLOR = vec4(waveColor, alpha * u_AccentColor.a);
            }
            """

        return AssetHandle(try ShaderSource(source: source))
    }
}
