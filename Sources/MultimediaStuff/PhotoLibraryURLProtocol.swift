//
//  PhotoLibraryURLProtocol.swift
//
//  Created by Sergey Starukhin on 03/11/2019.
//

import Foundation
import Photos
import CoreServices
import UIKit

@available(iOS 10.0, *)
public final class PhotoLibraryURLProtocol: URLProtocol, URLProtocolTools {
    
    enum Parameter: String {
        case id
        case ext
        
        func get(from url: URL) -> URLQueryItem? {
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                return components.queryItems?.first(where: { $0.name == self.rawValue })
            }
            return nil
        }
    }
    
    static public let scheme = "assets-library"
    static public let thumbnailFragment = "thumbnail"
    
    var requestId: PHImageRequestID? = nil
    
    var clientThread: Thread = .current
    var isNotCancelled: Bool = true
    
    override public class func canInit(with request: URLRequest) -> Bool {
        guard let scheme = request.url?.scheme else { return false }
        return scheme == PhotoLibraryURLProtocol.scheme
    }
    
    override public class func canInit(with task: URLSessionTask) -> Bool {
        guard let scheme = task.currentRequest?.url?.scheme else { return false }
        return scheme == PhotoLibraryURLProtocol.scheme
    }
    
    var assetLocalId: String {
        guard let url = request.url else { fatalError() }
        if let id = Parameter.id.get(from: url)?.value {
            return id
        }
        fatalError("Wrong url")
    }
    
    var manager: PHImageManager { PHImageManager.default() }
    
    lazy var options: PHImageRequestOptions = {
        let options = PHImageRequestOptions()
        options.isSynchronous = true
        options.isNetworkAccessAllowed = true
        return options
    }()
    
    var representation: UIImage.Representation = .png
    
    override public func startLoading() {
        clientThread = .current
        DispatchQueue.global().async {
            if let asset = PHAsset.fetchAssets(withLocalIdentifiers: [self.assetLocalId], options: nil).firstObject {
                if self.request.url?.fragment == PhotoLibraryURLProtocol.thumbnailFragment {
                    let scale = UIScreen.main.scale
                    let size = CGSize(width: 75 * scale, height: 75 * scale)
                    self.requestId = self.manager.requestImage(for: asset,
                                                               targetSize: size,
                                                               contentMode: .aspectFill,
                                                               options: self.options,
                                                               resultHandler: { self.handleThumbnail($0, info: $1) })
                } else {
                    self.requestId = self.manager.requestImageData(for: asset,
                                                                   options: self.options,
                                                                   resultHandler: { self.handleImageData($0, UTI: $1, orientation: $2, info: $3) })
                }
            } else {
                self.didFinishLoading(error: URLError(.resourceUnavailable))
            }
        }
    }
    
    override public func stopLoading() {
        isNotCancelled = false
        if let requestId = requestId {
            manager.cancelImageRequest(requestId)
        }
    }
    
    func handleThumbnail(_ image: UIImage?, info: [AnyHashable: Any]?) {
        guard let info = info as? [String : Any] else { fatalError() }
        if let isRequestCancelled = info[PHImageCancelledKey] as? Bool, isRequestCancelled {
            return
        }
        if let image = image {
            didLoad(data: image.data(representation), mimeType: representation.mimeType, cachePolicy: .allowedInMemoryOnly)
        } else {
            if let error = info[PHImageErrorKey] as? Error {
                didFinishLoading(error: error)
            } else {
                didFinishLoading(error: URLError(.resourceUnavailable))
            }
        }
    }
    
    func handleImageData(_ imageData: Data?, UTI: String?, orientation: UIImage.Orientation, info: [AnyHashable: Any]?) {
        guard let info = info as? [String : Any] else { fatalError() }
        if let isRequestCancelled = info[PHImageCancelledKey] as? Bool, isRequestCancelled {
            return
        }
        if let imageData = imageData, let uti = UTI {
            guard let mimeType = UTTypeCopyPreferredTagWithClass(uti as CFString, kUTTagClassMIMEType) else { fatalError("Wrong UTI: \(uti)") }
            didLoad(data: imageData, mimeType: mimeType.takeRetainedValue() as String, cachePolicy: .allowed)
        } else {
            if let error = info[PHImageErrorKey] as? Error {
                didFinishLoading(error: error)
            } else {
                didFinishLoading(error: URLError(.resourceUnavailable))
            }
        }
    }
}

@available(iOS 10.0, *)
extension PhotoLibraryURLProtocol {
    
    static public func makeUrlRepresentationAsset(_ localIdentifier: String, mediaType: PHAssetMediaType) -> URL {
        
        guard let uuid = UUID(uuidString: String(localIdentifier.prefix(36))) else { fatalError("Wrong identifier: \(localIdentifier)") }
        var queryItems = [ URLQueryItem(name: Parameter.id.rawValue, value: uuid.uuidString) ]
        
        var components = URLComponents()
        components.scheme = self.scheme
        components.host = "asset"
        switch mediaType {
        case .image:
            components.path = "/asset.JPG"
            queryItems.append(URLQueryItem(name: Parameter.ext.rawValue, value: "JPG"))
        case .video:
            components.path = "/asset.MOV"
            queryItems.append(URLQueryItem(name: Parameter.ext.rawValue, value: "MOV"))
        default:
            fatalError("Unsupported media type")
        }
        components.queryItems = queryItems
        if let url = components.url {
            return url
        }
        fatalError("Wrong url components: \(components)")
    }
}
