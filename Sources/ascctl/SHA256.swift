import Foundation

import Crypto

enum SHA256Hex {
    static func digest(_ data: Data) -> String {
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    static func digestString(_ string: String) -> String {
        digest(Data(string.utf8))
    }
}

