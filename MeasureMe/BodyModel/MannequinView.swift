// MannequinView.swift
//
// **MannequinView**
// SceneKit host for the body model.
//
// **Responsibilities:**
// - Owning the SCNView, camera and lighting
// - Swapping the geometry's position buffer as the morph moves
// - Re-resolving colours when the appearance changes
//
// **Why the appearance handling is explicit:**
// SCNView does not participate in SwiftUI's colour scheme propagation, so
// materials and the scene background stay at whatever they were built with.
// Without the explicit refresh in updateUIView, light mode renders a dark
// block. This is the only place in the feature where 3D steps outside the
// design system, and it is deliberately contained here.
//
import SwiftUI
import SceneKit

struct MannequinView: UIViewRepresentable {
    let parameters: BodyMeshParameters
    /// Horizontal rotation applied by the drag gesture.
    var rotationRadians: Double = 0

    @Environment(\.colorScheme) private var colorScheme

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = SCNScene()
        view.antialiasingMode = .multisampling2X
        view.isUserInteractionEnabled = false
        view.rendersContinuously = false

        let bodyNode = SCNNode(geometry: BodyGeometryBuilder.geometry(for: parameters))
        bodyNode.name = "body"
        view.scene?.rootNode.addChildNode(bodyNode)

        // Frame the body: the model is ~1.8 m tall and centred on the floor.
        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.orthographicScale = 1.15
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0.9, 3)
        view.scene?.rootNode.addChildNode(cameraNode)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 700
        key.position = SCNVector3(2, 3, 3)
        key.look(at: SCNVector3(0, 0.9, 0))
        view.scene?.rootNode.addChildNode(key)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 380
        view.scene?.rootNode.addChildNode(ambient)

        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        guard let bodyNode = view.scene?.rootNode.childNode(withName: "body", recursively: false) else { return }

        // Topology is fixed, so the geometry is rebuilt from the same layout
        // every frame of the morph — cheap at ~1500 vertices, and it keeps the
        // buffer handling in one place.
        bodyNode.geometry = BodyGeometryBuilder.geometry(for: parameters)
        bodyNode.eulerAngles.y = Float(rotationRadians)

        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = UIColor(FeatureTheme.photos.accent)
        material.roughness.contents = 0.85
        material.metalness.contents = 0.0
        material.isDoubleSided = true
        bodyNode.geometry?.materials = [material]

        view.backgroundColor = .clear
        view.scene?.background.contents = UIColor.clear
    }
}
