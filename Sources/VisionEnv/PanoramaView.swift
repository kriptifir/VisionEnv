import RealityKit
import SwiftUI
import UIKit

struct PanoramaView: View {
    static let immersiveSpaceID = "PanoramaSpace"

    @EnvironmentObject private var generator: EnvironmentGenerator

    var body: some View {
        Group {
            if generator.currentItem != nil {
                RealityView { content in
                    let root = Entity()
                    root.name = "PanoramaRoot"
                    content.add(root)

                    if let entity = try? await makePanoramaEntity() {
                        root.addChild(entity)
                    }
                }
                .id(generator.currentItem?.id)
            } else {
                Text("Generate an environment to enter the immersive space.")
                    .padding()
                    .glassBackgroundEffect()
                    .font(.title3)
            }
        }
    }

    private func makePanoramaEntity() async throws -> Entity {
        let entity = Entity()
        guard let fileURL = generator.imageFileURLForCurrentItem() else {
            return entity
        }

        let texture = try await TextureResource(contentsOf: fileURL)
        var material = UnlitMaterial()
        material.color = .init(texture: .init(texture))
        material.cullMode = .front

        let sphere = ModelEntity(
            mesh: .generateSphere(radius: 12),
            materials: [material]
        )
        sphere.scale = SIMD3<Float>(repeating: 1)
        entity.addChild(sphere)
        return entity
    }
}
