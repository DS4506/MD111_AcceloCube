
import SwiftUI
import SceneKit

// Renamed to avoid any "SceneViewBridge" redeclaration collisions
struct AcceloSceneView: UIViewRepresentable {
    @EnvironmentObject var vm: MotionVM

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = makeScene()
        view.allowsCameraControl = false
        view.autoenablesDefaultLighting = false
        view.backgroundColor = .black

        context.coordinator.cubeNode = view.scene?.rootNode.childNode(withName: "cube", recursively: true)
        context.coordinator.cameraNode = view.scene?.rootNode.childNode(withName: "camera", recursively: true)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        guard let cube = context.coordinator.cubeNode else { return }
        let q = vm.quat
        cube.orientation = SCNQuaternion(q.imag.x, q.imag.y, q.imag.z, q.real)
        cube.position = SCNVector3(vm.pos.x, vm.pos.y, vm.pos.z)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var cubeNode: SCNNode?
        var cameraNode: SCNNode?
    }

    // Scene content
    private func makeScene() -> SCNScene {
        let scene = SCNScene()

        // Floor (subtle)
        let floor = SCNFloor()
        floor.firstMaterial?.diffuse.contents = UIColor(white: 0.1, alpha: 1)
        floor.firstMaterial?.roughness.contents = 0.8
        let floorNode = SCNNode(geometry: floor)
        scene.rootNode.addChildNode(floorNode)

        // Cube
        let box = SCNBox(width: 0.1, height: 0.1, length: 0.1, chamferRadius: 0.01)
        let mat = SCNMaterial()
        mat.diffuse.contents = UIColor.systemTeal
        box.materials = [mat]
        let cubeNode = SCNNode(geometry: box)
        cubeNode.name = "cube"
        cubeNode.position = SCNVector3(0, 0.1, 0)
        scene.rootNode.addChildNode(cubeNode)

        // Lights
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 200
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        let directional = SCNLight()
        directional.type = .directional
        directional.intensity = 700
        let dirNode = SCNNode()
        dirNode.light = directional
        dirNode.eulerAngles = SCNVector3(-Float.pi/3, Float.pi/4, 0)
        scene.rootNode.addChildNode(dirNode)

        // Camera
        let camera = SCNCamera()
        camera.zNear = 0.01
        camera.zFar = 100
        camera.wantsHDR = true
        let camNode = SCNNode()
        camNode.name = "camera"
        camNode.camera = camera
        camNode.position = SCNVector3(0, 0.5, 2.0)
        camNode.look(at: SCNVector3(0, 0.1, 0))
        scene.rootNode.addChildNode(camNode)

        return scene
    }
}
