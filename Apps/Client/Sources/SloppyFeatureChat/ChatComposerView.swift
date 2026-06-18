import AdaEngine
import SloppyClientUI

@MainActor
public final class ChatComposerDraft {
    public var text: String
    
    public init(text: String = "") {
        self.text = text
    }
}

public struct ChatComposerView: View {
    public static let panelWidth: Float = 900
    public static let panelHeight: Float = 64
    public static let phonePanelHeight: Float = 72
    private static let panelRadius: Float = 32
    private static let fieldHeight: Float = 48
    private static let phoneFieldHeight: Float = 48
    private static let sendSize: Float = 38
    fileprivate static let phoneCircleSize: Float = 48
    
    @Environment(\.userInterfaceIdiom) private var idiom
    @Environment(\.theme) private var theme
    
    public let draft: ChatComposerDraft
    public let agentName: String
    public let onSend: (String) -> Void
    
    public init(
        draft: ChatComposerDraft,
        agentName: String = "Agent",
        onSend: @escaping (String) -> Void
    ) {
        self.draft = draft
        self.agentName = agentName
        self.onSend = onSend
    }
    
    @ViewBuilder
    public var body: some View {
        if idiom == .phone {
            phoneBody
        } else {
            regularBody
        }
    }
    
    private var phoneBody: some View {
        let c = theme.colors
        let sp = theme.spacing
        let ty = theme.typography
        let fieldInk = c.textPrimary
        
        return HStack(spacing: sp.s) {
            MobileComposerCircleButton(symbol: .add, action: {})
            
            TextField(
                "Ask \(agentDisplayName)",
                text: Binding(
                    get: { draft.text },
                    set: { draft.text = $0 }
                )
            )
            .font(.system(size: ty.body))
            .foregroundColor(fieldInk)
            .accentColor(.white)
            .textFieldStyle(PlainTextFieldStyle())
            .frame(
                minWidth: 0, maxWidth: .infinity, minHeight: Self.phoneFieldHeight,
                maxHeight: Self.phoneFieldHeight, alignment: .leading
            )
            .padding(.horizontal, sp.m)
            .glassEffect(.regular, in: .capsule)
            .frame(maxWidth: .infinity, alignment: .leading)
            
            MobileComposerCircleButton(
                symbol: .arrowUpward,
                foregroundColor: draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? c.textMuted
                : c.textPrimary,
                fillColor: c.surfaceRaised,
                action: submit
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, sp.xs)
        .padding(.vertical, sp.s)
        .frame(
            minWidth: 0,
            maxWidth: .infinity,
            minHeight: Self.phonePanelHeight,
            maxHeight: Self.phonePanelHeight,
            alignment: .leading
        )
    }
    
    private var regularBody: some View {
        let c = theme.colors
        let sp = theme.spacing
        let ty = theme.typography
        let fieldInk = c.textPrimary
        let actionInk = c.textPrimary
        let actionFill = Color.fromHex(0xA7DFFF)
        
        return HStack(spacing: sp.m) {
            Button(action: {}) {
                Icons.symbol(.add, size: 28)
                    .foregroundColor(actionInk)
                    .frame(width: Self.sendSize, height: Self.sendSize)
            }
            
            TextField(
                "Ask \(agentDisplayName)",
                text: Binding(
                    get: { draft.text },
                    set: { draft.text = $0 }
                )
            )
            .font(.system(size: ty.body))
            .foregroundColor(fieldInk)
            .accentColor(.white)
            .textFieldStyle(PlainTextFieldStyle())
            .frame(
                minWidth: 0, maxWidth: .infinity, minHeight: Self.fieldHeight,
                maxHeight: Self.fieldHeight, alignment: .leading
            )
            Button(action: submit) {
                Icons.symbol(.arrowUpward, size: ty.heading)
                    .foregroundColor(actionInk)
                    .frame(width: Self.sendSize, height: Self.sendSize)
                    .glassEffect(
                        .regular.tint(actionFill), in: .rect(cornerRadius: Self.sendSize / 2)
                    )
            }
        }
        .padding(EdgeInsets(top: 0, leading: sp.l + sp.s, bottom: 0, trailing: sp.s + sp.s))
        .frame(
            minWidth: 0,
            maxWidth: .infinity,
            minHeight: Self.panelHeight,
            maxHeight: Self.panelHeight,
            alignment: .leading
        )
        .background {
            ChatComposerCapsuleChrome(
                height: Self.panelHeight,
                aspectRatio: Self.panelWidth / Self.panelHeight,
                accentColor: c.accentCyan
            )
        }
        .frame(maxWidth: Self.panelWidth)
    }
    
    private var agentDisplayName: String {
        agentName.isEmpty ? "Sloppy" : agentName
    }
    
    public static func panelHeight(for idiom: UserInterfaceIdiom) -> Float {
        idiom == .phone ? phonePanelHeight : panelHeight
    }
    
    private func submit() {
        let trimmed = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSend(trimmed)
        draft.text = ""
    }
}

private struct MobileComposerCircleButton: View {
    let symbol: MaterialSymbol
    var foregroundColor: Color = Theme.sloppyDark.colors.textPrimary
    var fillColor: Color = Color.fromHex(0x1C1C1E).opacity(0.96 as Float)
    let action: @MainActor () -> Void
    
    @Environment(\.theme) private var theme
    
    var body: some View {
        Button(action: action) {
            Icons.symbol(symbol, size: theme.typography.heading)
                .foregroundColor(foregroundColor)
                .frame(width: ChatComposerView.phoneCircleSize, height: ChatComposerView.phoneCircleSize)
                .background {
                    Circle()
                        .fill(fillColor)
                }
        }
        .glassEffect(.regular, in: Circle())
        .buttonStyle(DefaultButtonStyle())
    }
}

private struct ChatComposerCapsuleChrome: View {
    let height: Float
    let aspectRatio: Float
    let accentColor: Color
    
    var body: some View {
        ZStack {
            Capsule()
                .fill(Color.black)
            
            //            ChatComposerCapsuleGlow(
            //                height: height,
            //                aspectRatio: aspectRatio,
            //                accentColor: accentColor
            //            )
        }
    }
}

private struct ChatComposerCapsuleGlow: View {
    private static let verticalGlowOutset: Float = 28
    
    let height: Float
    let aspectRatio: Float
    let accentColor: Color
    
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
            let time = Float(
                context.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 4096)
            )
            let overlayHeight = height + Self.verticalGlowOutset
            let capsuleRadius = height / overlayHeight
            let overlayAspectRatio = aspectRatio * capsuleRadius
            
            RectangleShape()
                .fill(Color.white)
                .shaderEffect(
                    CustomMaterial(
                        ChatComposerCapsuleGlowMaterial(
                            time: time,
                            accentColor: accentColor,
                            aspectRatio: overlayAspectRatio,
                            capsuleRadius: capsuleRadius
                        )
                    ),
                    placement: .overlay
                )
                .frame(maxWidth: .infinity, minHeight: overlayHeight, maxHeight: overlayHeight)
        }
    }
}

private struct ChatComposerCapsuleGlowMaterial: UIShaderMaterial {
    @Uniform(binding: 0, propertyName: "u_Time")
    var time: Float
    
    @Uniform(binding: 0, propertyName: "u_AccentColor")
    var accentColor: Color
    
    @Uniform(binding: 0, propertyName: "u_AspectRatio")
    var aspectRatio: Float
    
    @Uniform(binding: 0, propertyName: "u_CapsuleRadius")
    var capsuleRadius: Float
    
    init(time: Float, accentColor: Color, aspectRatio: Float, capsuleRadius: Float) {
        self.time = time
        self.accentColor = accentColor
        self.aspectRatio = aspectRatio
        self.capsuleRadius = capsuleRadius
    }
    
    static func vertexShader() throws -> AssetHandle<ShaderSource> {
        let source = """
            #version 450 core
            #pragma stage : vert
            
            #include <AdaEngine/View.glsl>
            
            layout (location = 0) in vec4 a_Position;
            layout (location = 1) in vec4 a_Color;
            layout (location = 2) in vec2 a_TexCoordinate;
            
            layout (location = 0) out vec4 Output_Color;
            layout (location = 1) out vec2 Output_UV;
            
            [[main]]
            void chat_composer_capsule_glow_vertex()
            {
                Output_Color = a_Color;
                Output_UV = a_TexCoordinate;
                gl_Position = u_ViewProjection * a_Position;
            }
            """
        
        return AssetHandle(try ShaderSource(source: source))
    }
    
    static func fragmentShader() throws -> AssetHandle<ShaderSource> {
        let source = """
            #version 450 core
            #pragma stage : frag
            
            layout (location = 0) in vec4 Input_Color;
            layout (location = 1) in vec2 Input_UV;
            layout (location = 0) out vec4 COLOR;
            
            layout (binding = 0) uniform ChatComposerCapsuleGlowMaterial {
                float u_Time;
                vec4 u_AccentColor;
                float u_AspectRatio;
                float u_CapsuleRadius;
            };
            
            [[main]]
            void chat_composer_capsule_glow_fragment()
            {
                vec2 uv = Input_UV;
                float t = u_Time * 0.58;
            
                // Work in centered overlay coordinates. The overlay is taller than
                // the actual composer; u_CapsuleRadius keeps the SDF on the real
                // capsule instead of stretching the border into a pill-shaped blob.
                vec2 p = uv * 2.0 - 1.0;
                p.x *= max(u_AspectRatio, 1.0);
            
                float radius = clamp(u_CapsuleRadius, 0.38, 0.92);
                float halfLength = max(u_AspectRatio - radius, 0.0);
                vec2 q = vec2(abs(p.x) - halfLength, abs(p.y)) - vec2(0.0, radius);
                float capsuleDistance = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
            
                // A crisp 1-2px line plus a separated soft outer bloom. Keeping the
                // halo mostly outside avoids washing the whole input black/blue.
                float edge = 1.0 - smoothstep(0.004, 0.030, abs(capsuleDistance));
                float outer = max(capsuleDistance, 0.0);
                float closeBloom = (1.0 - smoothstep(0.010, 0.150, outer)) * smoothstep(-0.025, 0.010, capsuleDistance);
                float farBloom = (1.0 - smoothstep(0.080, 0.430, outer)) * smoothstep(0.010, 0.080, outer);
            
                float angle = atan(p.y / max(radius, 0.001), p.x / max(u_AspectRatio, 0.001));
                float wave = sin(angle * 2.0 - t * 2.4 + p.x * 0.42);
                float travellingBand = smoothstep(0.45, 1.0, wave * 0.5 + 0.5);
                float fineLines = 0.72 + 0.28 * sin((length(p) - t * 0.18) * 54.0 + angle * 3.0);
            
                vec3 cyan = mix(u_AccentColor.rgb, vec3(0.40, 0.92, 1.0), 0.72);
                vec3 violet = vec3(0.55, 0.34, 1.0);
                vec3 magenta = vec3(1.0, 0.18, 0.58);
                vec3 blue = vec3(0.08, 0.34, 1.0);
                vec3 borderColor = mix(cyan, violet, smoothstep(-1.0, 1.0, sin(angle + t * 0.65)));
                borderColor = mix(borderColor, magenta, travellingBand * 0.42);
                borderColor = mix(borderColor, blue, smoothstep(-u_AspectRatio, u_AspectRatio, p.x) * 0.18);
            
                float alpha = clamp(edge * (0.86 + travellingBand * 0.14) + closeBloom * 0.34 + farBloom * 0.22, 0.0, 0.95);
                vec3 color = borderColor * (edge * 1.25 + closeBloom * 0.78 + farBloom * 0.44) * fineLines;
            
                COLOR = vec4(color * Input_Color.rgb, alpha * Input_Color.a);
            
                if (COLOR.a <= 0.001) {
                    discard;
                }
            }
            """
        
        return AssetHandle(try ShaderSource(source: source))
    }
}
