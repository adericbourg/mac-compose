import Foundation

public func bundledResource(_ name: String) -> URL? {
    Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Resources")
}
