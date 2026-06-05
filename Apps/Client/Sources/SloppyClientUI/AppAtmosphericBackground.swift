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

            TimelineView(.animation) { context in
                // Keep shader time small before converting to Float.
                // `timeIntervalSinceReferenceDate` is a large value and Float loses
                // sub-second precision there, making animated uniforms look static.
                let animatedTime = Float(
                    context.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: 4096)
                )

                Color.clear
                    .shaderEffect(
                        CustomMaterial(
                            AppAtmosphericBackgroundMaterial(
                                time: animatedTime,
                                accentColor: accentColor
                            )
                        ),
                        placement: .overlay
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            }
            .ignoresSafeArea()
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
