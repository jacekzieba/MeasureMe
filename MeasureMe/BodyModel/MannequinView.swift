// MannequinView.swift
//
// **MannequinView**
// SceneKit host for the body model.
//
// **Responsibilities:**
// - Owning the SCNView, camera and lighting
// - Building the geometry from the baked base mesh at the measured stature
// - Re-resolving colours when the appearance changes
//
// **Why the appearance handling is explicit:**
// SCNView does not participate in SwiftUI's colour scheme propagation, so
// materials and the scene background stay at whatever they were built with.
// Without the explicit refresh in updateUIView, light mode renders a dark
// block. This is the only place in the feature where 3D steps outside the
// design system, and it is deliberately contained here.
//
// **Stage 1 caveat:**
// Measurements do not reach the shape yet — the mesh is the base body scaled
// to stature. `BodyMeshSolver` still runs and still feeds the volume
// validator; wiring its circumferences into the vertices is stage 2's job.
//
import SwiftUI
import SceneKit

struct MannequinView: UIViewRepresentable {
    let parameters: BodyMeshParameters
    let gender: BodyGender
    /// Horizontal rotation applied by the drag gesture.
    var rotationRadians: Double = 0

    @Environment(\.colorScheme) private var colorScheme

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = SCNScene()
        view.antialiasingMode = .multisampling2X
        view.isUserInteractionEnabled = false
        view.rendersContinuously = false

        let bodyNode = SCNNode(geometry: geometry())
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

        // Three directional lights so the silhouette reads in both themes: a
        // key, a cooler fill opposite it, and a rim from behind that separates
        // the shoulders from the card background.
        for (index, setup) in [(700.0, SCNVector3(2, 3, 3)),
                               (260.0, SCNVector3(-3, 2, 1)),
                               (180.0, SCNVector3(0, 2, -4))].enumerated() {
            let node = SCNNode()
            node.light = SCNLight()
            node.light?.type = .directional
            node.light?.intensity = setup.0
            node.position = setup.1
            node.look(at: SCNVector3(0, 0.9, 0))
            // Only the key casts: three shadow-casting lights would give the
            // body three overlapping shadows.
            if index == 0 {
                node.light?.castsShadow = true
                node.light?.shadowMode = .deferred
                node.light?.shadowRadius = 12
                node.light?.shadowColor = UIColor.black.withAlphaComponent(0.35)
            }
            view.scene?.rootNode.addChildNode(node)
        }

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 300
        view.scene?.rootNode.addChildNode(ambient)

        // A shadow catcher: `.deferred` draws the shadow without lighting the
        // plane itself, so the floor never appears — only the darkening under
        // the feet, which is the only cue that the body is standing on
        // something rather than hovering.
        let floor = SCNNode(geometry: SCNPlane(width: 4, height: 4))
        floor.eulerAngles.x = -.pi / 2
        floor.geometry?.firstMaterial?.lightingModel = .constant
        floor.geometry?.firstMaterial?.writesToDepthBuffer = false
        floor.geometry?.firstMaterial?.colorBufferWriteMask = []
        floor.castsShadow = false
        view.scene?.rootNode.addChildNode(floor)

        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        guard let bodyNode = view.scene?.rootNode.childNode(withName: "body", recursively: false) else { return }

        bodyNode.geometry = geometry()
        bodyNode.eulerAngles.y = Float(rotationRadians)

        // A matte, near-neutral clay. Deliberately not skin: a half-realistic
        // skin tone on a body that is not actually the user's reads as uncanny,
        // where clay reads as a model of a body, which is what this is.
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = UIColor(red: 0.78, green: 0.76, blue: 0.73, alpha: 1)
        material.roughness.contents = 0.65
        material.metalness.contents = 0.0
        // The base mesh is a closed volume, so back faces are never meant to be
        // seen; double-siding was only ever hiding the old open-ended tubes.
        material.isDoubleSided = false
        bodyNode.geometry?.materials = [material]

        view.backgroundColor = .clear
        view.scene?.background.contents = UIColor.clear
    }

    private func geometry() -> SCNGeometry? {
        guard let mesh = try? BodyBaseMeshProvider.mesh(for: gender),
              let rig = try? BodyBaseMeshProvider.rig(for: gender)
        else { return nil }

        let positions = BodyMeshDeformer.deform(
            mesh: mesh, map: rig.map, profile: rig.profile, parameters: parameters
        )
        // The baked normals describe the base surface and stop matching it the
        // moment the measurements move a vertex, so they are rebuilt here.
        let normals = BodyMeshDeformer.normals(for: positions, indices: mesh.indices)

        return SCNGeometry(
            sources: [
                SCNGeometrySource(vertices: positions.map { SCNVector3($0.x, $0.y, $0.z) }),
                SCNGeometrySource(normals: normals.map { SCNVector3($0.x, $0.y, $0.z) })
            ],
            elements: [SCNGeometryElement(indices: mesh.indices, primitiveType: .triangles)]
        )
    }
}
