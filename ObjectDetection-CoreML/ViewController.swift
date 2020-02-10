//
//  ViewController.swift
//  SSDMobileNet-CoreML
//
//  Created by GwakDoyoung on 01/02/2019.
//  Copyright © 2019 tucan9389. All rights reserved.
//

import UIKit
import ARKit
import Fritz
import RealityKit
import SceneKit.ModelIO
import Vision
import CoreMedia

class ViewController: UIViewController , ARSCNViewDelegate, ARSessionDelegate{

    // MARK: - UI Properties
    @IBOutlet weak var boxesView: DrawingBoundingBoxView!
    @IBOutlet weak var sceneView: ARSCNView!
    
    let objectDectectionModel = YOLOv3()
    let depthDetectionModel = DeepLabV3()
    var planeColor = UIColor.init(hue: 0.5, saturation: 0.5, brightness: 0.5, alpha: 0.5)
    private lazy var fritzModel = FritzVisionPeopleSegmentationModelFast()
    var maxPlanesCount = 5
    var currentPlaneCount = 0
    let visionQueue = DispatchQueue(label: "com.vision.ARML.visionqueue")
    
    
    // MARK: - Vision Properties
    var request: VNCoreMLRequest?
    var visionModel: VNCoreMLModel?
    var isInferencing = false
    var currentFrameBuffer: CVPixelBuffer?
    
    // MARK: - AV Property
    var videoCapture: VideoCapture!
    let planesRootNode = SCNNode()
    
    var fritzMaskNode : SCNNode!
    var fritzMaskMaterial : SCNMaterial!
    
    // MARK: - TableView Data
    var predictions: [VNRecognizedObjectObservation] = []
    
    // MARK - Performance Measurement Property
    //private let 👨‍🔧 = 📏()
    
    let configuration = ARWorldTrackingConfiguration()
    
    // MARK: - View Controller Life Cycle
    override func viewDidLoad() {
        super.viewDidLoad()
        let vaseScene = SCNScene(named:"IronMan/IronMan.scn")
        guard let node =  vaseScene?.rootNode else { return }

        
        sceneView.delegate = self
        sceneView.session.delegate = self
        //sceneView.showsStatistics = true

       let scene = SCNScene()

        sceneView.scene = scene
        sceneView.scene.rootNode.addChildNode(node)
        //sceneView.scene.rootNode.addChildNode(planesRootNode)
        sceneView.pointOfView?.presentation.addChildNode(planesRootNode)

        setUpModel()
        self.bilbordCreate()
        FritzCore.configure()
        
    }
    
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.sceneView.session.run(configuration)

        
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sceneView.session.pause()
    }
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {

        guard currentFrameBuffer == nil, case .normal = frame.camera.trackingState else {
            return
        }
        currentFrameBuffer = frame.capturedImage
        self.updateCoreML()
    }
        
    func bilbordCreate() {
        fritzMaskMaterial = SCNMaterial()
        fritzMaskMaterial.diffuse.contents = UIColor.white
        fritzMaskMaterial.colorBufferWriteMask = .alpha
        
        let rectangle = SCNPlane(width: 0.0326, height: 0.058)
        rectangle.materials = [fritzMaskMaterial]
        
        fritzMaskNode = SCNNode(geometry: rectangle)
        fritzMaskNode?.eulerAngles = SCNVector3Make(0, 0, 0)
        fritzMaskNode?.position = SCNVector3Make(0, 0, -0.05)
        fritzMaskNode.renderingOrder = -1
        
        sceneView.pointOfView?.presentation.addChildNode(fritzMaskNode!)
    }
    
    
    // MARK: - Setup Core ML
    func setUpModel() {
        if let visionModel = try? VNCoreMLModel(for: objectDectectionModel.model) {
            self.visionModel = visionModel
            request = VNCoreMLRequest(model: visionModel, completionHandler: visionRequestDidComplete)
            request?.imageCropAndScaleOption = .scaleFill
        } else {
            fatalError("fail to create vision model")
        }
    }
}


extension ViewController {
    func predictUsingVision(imageFromArkitScene: CVPixelBuffer) {
        guard let request = request else { fatalError() }
        // vision framework configures the input size of image following our model's input configuration automatically
        let handler = VNImageRequestHandler(cvPixelBuffer: imageFromArkitScene, orientation: .right)
        try? handler.perform([request])

    }
    
    
    // MARK: - Post-processing
    func visionRequestDidComplete(request: VNRequest, error: Error?) {
        if let predictions = request.results as? [VNRecognizedObjectObservation] {
            self.predictions = predictions
            self.maxPlanesCount = predictions.count
            self.boxesView.subviews.forEach({ $0.removeFromSuperview() })
            for prediction in self.predictions{
                let rect: CGRect = self.boxesView.createLabelAndBox(prediction: prediction)
                self.addPlane(rect: rect)
            }
            self.isInferencing = false
        } else {
            
            self.isInferencing = false
        }
    }
    
    private func FritzCoreMLRequest(image : FritzVisionImage, options : FritzVisionSegmentationModelOptions) {
        
        guard let result = try? self.fritzModel.predict(image, options: options) else {
            self.ReleaseBuffer()
            return
        }
        
        let maskImage = result.buildSingleClassMask(
            forClass: FritzVisionPeopleClass.person,
            clippingScoresAbove: 0.7,
            zeroingScoresBelow: 0.3)
        
        guard let CIRef = maskImage?.ciImage else {
            self.ReleaseBuffer()
            return
        }
        guard let maskCGImage: CGImage = self.convertCIImageToCGImage(inputImage: CIRef) else {
            self.ReleaseBuffer()
            return
        }

        DispatchQueue.main.async {
            self.fritzMaskMaterial.diffuse.contents = maskCGImage
        }
        
        self.ReleaseBuffer()

    }
    

    
    
    func convertCIImageToCGImage(inputImage: CIImage) -> CGImage? {
        let context = CIContext(options: nil)
        if let cgImage = context.createCGImage(inputImage, from: inputImage.extent) {
            return cgImage
        }
        return nil
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        guard let planeAnchor = anchor as? ARPlaneAnchor else { return }
        print("oyeaaa###########")
        let width = CGFloat(planeAnchor.extent.x)
        let height = CGFloat(planeAnchor.extent.z)
        let plane = SCNPlane(width: width, height: height)
        
        plane.materials.first?.diffuse.contents = planeColor
        
        let planeNode = SCNNode(geometry: plane)
        
        let x = CGFloat(planeAnchor.center.x)
        let y = CGFloat(planeAnchor.center.y)
        let z = CGFloat(planeAnchor.center.z)
        planeNode.position = SCNVector3(x,y,z)
        planeNode.eulerAngles.x = -.pi / 2
        
        node.addChildNode(planeNode)
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let planeAnchor = anchor as?  ARPlaneAnchor,
            let planeNode = node.childNodes.first,
            let plane = planeNode.geometry as? SCNPlane
            else { return }
        print("oyeaaa###########")
        let width = CGFloat(planeAnchor.extent.x)
        let height = CGFloat(planeAnchor.extent.z)
        plane.width = width
        plane.height = height
        
        let x = CGFloat(planeAnchor.center.x)
        let y = CGFloat(planeAnchor.center.y)
        let z = CGFloat(planeAnchor.center.z)
        planeNode.position = SCNVector3(x, y, z)
    }
    
    private func ReleaseBuffer() {
         // The resulting image (mask) is available as observation.pixelBuffer
         // Release currentBuffer when finished to allow processing next frame
         self.currentFrameBuffer = nil
     }
    
    func addPlane(rect : CGRect){

        let screenCentre : CGPoint = CGPoint(x: rect.midX, y: rect.midY)
        let planeorigin : CGPoint = rect.origin
        let rightbottom : CGPoint = CGPoint(x: rect.maxX, y: rect.maxY)
        let centerTestResults : [ARHitTestResult] = sceneView.hitTest(screenCentre, types: [.featurePoint]) // Alternatively, we could use '.existingPlaneUsingExtent' for more grounded hit-test-points.
        let originTestResults : [ARHitTestResult] = sceneView.hitTest(planeorigin, types: [.featurePoint])
        let rightbotTestResults : [ARHitTestResult] = sceneView.hitTest(rightbottom, types: [.featurePoint])
        if let closestResult = centerTestResults.first {
            if let originResult = originTestResults.first{
                if let rightbotResult = rightbotTestResults.first{
                    
                    
                    let originTransform : matrix_float4x4 = originResult.worldTransform
                    let rightbotTransform : matrix_float4x4 = rightbotResult.worldTransform
                    let width : CGFloat = CGFloat(abs(rightbotTransform.columns.3.x - originTransform.columns.3.x))
                    let height : CGFloat = CGFloat(abs(originTransform.columns.3.y - rightbotTransform.columns.3.y))
                    
                    let transform : matrix_float4x4 = closestResult.worldTransform
                    let worldCoord : SCNVector3 = SCNVector3Make(transform.columns.3.x, transform.columns.3.y, (transform.columns.3.z + originTransform.columns.3.z + rightbotTransform.columns.3.z)/3.0)
                    // Create 3D Text
                    let node : SCNNode = createPlane(rect: rect, coordinate: worldCoord, planeWidth: width, planeHeight: height)
                    //node.geometry?.firstMaterial = maskMaterial()
                    
                    if planesRootNode.childNodes.count > maxPlanesCount
                    {
                        planesRootNode.replaceChildNode(planesRootNode.childNodes[currentPlaneCount], with: node)
                        currentPlaneCount += 1
                        currentPlaneCount %= maxPlanesCount
                    }
                    else
                    {
                        planesRootNode.addChildNode(node)
                    }
                }
            }
            else{
                
                let transform : matrix_float4x4 = closestResult.worldTransform
                let worldCoord : SCNVector3 = SCNVector3Make(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
                // Create 3D Text
                let node : SCNNode = createPlane(rect: rect, coordinate: worldCoord, planeWidth: 0.2, planeHeight: 0.2)
                //node.geometry?.firstMaterial = maskMaterial()


                if planesRootNode.childNodes.count > maxPlanesCount
                {
                     planesRootNode.replaceChildNode(planesRootNode.childNodes[currentPlaneCount], with: node)
                    currentPlaneCount += 1
                    currentPlaneCount %= maxPlanesCount
                }
                else
                {
                    planesRootNode.addChildNode(node)
                }

            }
        }
    }
    
    func createPlane(rect : CGRect, coordinate: SCNVector3, planeWidth : CGFloat, planeHeight : CGFloat) -> SCNNode
    {
        let plane = SCNPlane(width: planeWidth, height: planeHeight)
        plane.cornerRadius = 0.005
        let planeNode = SCNNode(geometry: plane)
        planeNode.geometry?.firstMaterial?.isDoubleSided = true
        //planeNode.geometry?.firstMaterial?.colorBufferWriteMask = .alpha
        planeNode.geometry?.firstMaterial?.writesToDepthBuffer = true
        planeNode.geometry?.firstMaterial?.readsFromDepthBuffer = true
        planeNode.renderingOrder = -100
        planeNode.geometry?.firstMaterial?.diffuse.contents = UIColor.orange
        planeNode.position = coordinate
        return planeNode
    }
    
    func maskMaterial() -> SCNMaterial {
        let maskMaterial = SCNMaterial()
        maskMaterial.diffuse.contents = UIColor.white
        maskMaterial.isDoubleSided = true
        return maskMaterial
    }
    //MARK: - updatePredictionByARscene
    func updateCoreML() {

        guard let buffer = currentFrameBuffer else { return }
        self.predictUsingVision(imageFromArkitScene: buffer)
        let fritzImage = FritzVisionImage(imageBuffer: buffer)
        fritzImage.metadata = FritzVisionImageMetadata()
        let options = FritzVisionSegmentationModelOptions()
        options.imageCropAndScaleOption = .scaleFit
        visionQueue.async {
            self.FritzCoreMLRequest(image: fritzImage, options: options)
        }

    }
}



