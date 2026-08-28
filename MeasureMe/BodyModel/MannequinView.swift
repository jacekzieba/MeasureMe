// MannequinView.swift
//
// **MannequinView**
// SceneKit host for the body model.
//
// **Responsibilities:**
// - Owning the SCNView, camera and lighting
// - Building the geometry from the baked base mesh at the measured stature
// - Rebuilding geometry only when the measurements or gender change
//
// **Why the appearance handling is explicit:**
// SCNView does not participate in SwiftUI's colour scheme propagation, so
// materials and the scene background stay at whatever they were built with.
// Without the explicit refresh in updateUIView, light mode renders a dark
// block. This is the only place in the feature where 3D steps outside the
// design system, and it is deliberately contained here.
//
// **Why the pan recognizer is UIKit's rather than SwiftUI's:**
// The card sits in a ScrollView, and a SwiftUI `.gesture` loses arbitration to
// the scroll pan. Worse, the SCNView had touches disabled, so it was invisible
// to hit testing and the gesture never fired at all. A recognizer owned by the
// view sidesteps both, and turns the node directly instead of routing an angle
// back through SwiftUI state.
//
// **Why geometry is cached rather than rebuilt:**
// A drag must not touch the mesh. Deforming 13 380 vertices and re-accumulating
// normals over 26 756 triangles per frame is what made rotation unusable on
// device; the coordinator holds the built geometry and rotation only sets the
// node's euler angle.
//
import SwiftUI
import SceneKit

struct MannequinView: UIViewRepresentable {
    let parameters: BodyMeshParameters
    let gender: BodyGender

    @Environment(\.colorScheme) private var colorScheme

    /// Caches the built geometry so a drag does not rebuild it.
    ///
    /// Deforming 13 380 vertices and re-accumulating normals over 26 756
    /// triangles per frame is what made rotation unusable on device: the old
    /// ring-stack was ~1 500 vertices, so rebuilding it every update was
    /// tolerable, and this mesh is nine times heavier. Rotation only ever needs
    /// the node's euler angle.
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parameters: BodyMeshParameters?
        var gender: BodyGender?
        var geometry: SCNGeometry?
        weak var bodyNode: SCNNode?
        /// Where the previous drag left the body.
        var committed: Double = 0

        /// Turns the node directly. Nothing round-trips through SwiftUI state,
        /// so a drag never triggers `updateUIView` and never re-checks geometry.
        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard let node = bodyNode else { return }
            let width = Double(recognizer.translation(in: recognizer.view).x)
            let angle = MannequinRotation.angle(committed: committed, dragWidth: width)
            node.eulerAngles.y = Float(angle)
            if recognizer.state == .ended || recognizer.state == .cancelled {
                committed = MannequinRotation.normalised(angle)
            }
        }

        /// Claims only predominantly horizontal drags, so a vertical swipe still
        /// scrolls the page this 380 pt card sits in.
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = SCNScene()
        view.antialiasingMode = .multisampling4X
        // Must be true. With touches disabled the view is invisible to hit
        // testing, so a SwiftUI gesture attached to it never fires — which is
        // why two attempts at fixing rotation in SwiftUI changed nothing.
        view.isUserInteractionEnabled = true
        view.rendersContinuously = false

        let initial = geometry()
        initial?.materials = [clayMaterial()]
        let bodyNode = SCNNode(geometry: initial)
        bodyNode.name = "body"
        view.scene?.rootNode.addChildNode(bodyNode)
        context.coordinator.bodyNode = bodyNode

        // A UIKit recognizer straight on the view. SwiftUI gesture arbitration
        // against the enclosing ScrollView is bypassed entirely rather than
        // negotiated with.
        let pan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)

        // Frame the body: the model is ~1.8 m tall and centred on the floor.
        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.orthographicScale = 1.15
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        // Ambient occlusion. Without it the clay reads flat: there is nothing
        // darkening the crease behind a knee or between the legs, so the form
        // has no depth cue beyond its outline.
        camera.screenSpaceAmbientOcclusionIntensity = 1.4
        camera.screenSpaceAmbientOcclusionRadius = 0.12
        camera.screenSpaceAmbientOcclusionBias = 0.03
        cameraNode.position = SCNVector3(0, 0.9, 3)
        view.scene?.rootNode.addChildNode(cameraNode)

        // Three directional lights so the silhouette reads in both themes: a
        // key, a cooler fill opposite it, and a rim from behind that separates
        // the shoulders from the card background.
        //
        // **The rim is 60, not 180, and that number is the whole fix for the
        // white gash along the top of the shoulder.** It was diagnosed as a
        // fold baked into the mesh and it is not: the line survives every
        // subdivision level, roughness and key intensity — none of which touch
        // a rim highlight on a surface curving away from the camera — and the
        // mesh has zero split vertices. Rendered with the rim at 0 it is simply
        // gone. Sixty keeps the separation the rim is here for and leaves only
        // a trace of the highlight.
        //
        // None of them casts. The camera is orthographic and looks horizontally,
        // so a ground plane is seen exactly edge-on — a contact shadow under the
        // feet is geometrically invisible from here, whether cast by SceneKit or
        // painted onto a quad. Both were tried. Giving the body one means tilting
        // the camera down a few degrees, which changes how the proportions read.
        for (index, setup) in [(700.0, SCNVector3(2, 3, 3)),
                               (260.0, SCNVector3(-3, 2, 1)),
                               (60.0, SCNVector3(0, 2, -4))].enumerated() {
            let node = SCNNode()
            node.light = SCNLight()
            node.light?.type = .directional
            node.light?.intensity = setup.0
            node.position = setup.1
            node.look(at: SCNVector3(0, 0.9, 0))
            view.scene?.rootNode.addChildNode(node)
        }

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 300
        view.scene?.rootNode.addChildNode(ambient)

        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        guard let bodyNode = view.scene?.rootNode.childNode(withName: "body", recursively: false) else { return }

        let coordinator = context.coordinator
        if coordinator.parameters != parameters || coordinator.gender != gender {
            let built = geometry()
            built?.materials = [clayMaterial()]
            coordinator.parameters = parameters
            coordinator.gender = gender
            coordinator.geometry = built
            bodyNode.geometry = built
        } else if bodyNode.geometry == nil, let cached = coordinator.geometry {
            bodyNode.geometry = cached
        }
        coordinator.bodyNode = bodyNode

        view.backgroundColor = .clear
        view.scene?.background.contents = UIColor.clear
    }

    /// A matte, near-neutral clay. Deliberately not skin: a half-realistic skin
    /// tone on a body that is not actually the user's reads as uncanny, where
    /// clay reads as a model of a body, which is what this is.
    private func clayMaterial() -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = UIColor(red: 0.78, green: 0.76, blue: 0.73, alpha: 1)
        material.roughness.contents = 0.65
        material.metalness.contents = 0.0
        // The base mesh is a closed volume, so back faces are never meant to be
        // seen; double-siding was only ever hiding the old open-ended tubes.
        material.isDoubleSided = false
        return material
    }

    private func geometry() -> SCNGeometry? {
        // Never builds the rig here. If it is not prepared yet the screen is
        // showing its loading state, and blocking to build it would freeze the
        // very frame that draws the indicator.
        guard let prepared = BodyBaseMeshProvider.prepared(
            for: gender, fatness: parameters.fatness
        ) else { return nil }
        let mesh = prepared.mesh

        let positions = BodyMeshDeformer.deform(
            mesh: mesh, map: prepared.map, profile: prepared.profile, parameters: parameters
        )
        // The baked normals describe the base surface and stop matching it the
        // moment the measurements move a vertex, so they are rebuilt here.
        let normals = BodyMeshDeformer.normals(for: positions, indices: mesh.indices)

        let geometry = SCNGeometry(
            sources: [
                SCNGeometrySource(vertices: positions.map { SCNVector3($0.x, $0.y, $0.z) }),
                SCNGeometrySource(normals: normals.map { SCNVector3($0.x, $0.y, $0.z) })
            ],
            elements: [SCNGeometryElement(indices: mesh.indices, primitiveType: .triangles)]
        )
        // Smooths the silhouette on the GPU. The deformer still works on 13 380
        // vertices, so nothing on the CPU gets more expensive.
        geometry.subdivisionLevel = 1
        return geometry
    }
}
