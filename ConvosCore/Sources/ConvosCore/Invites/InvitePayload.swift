import Foundation

// MARK: - Models (unchanged)
public struct SignedInvite: Codable {
    public let payload: InvitePayload
    public let signature: Data
}

public struct InvitePayload: Codable {
    public let code: String
    public let creatorInboxId: String
}

// MARK: - Short, unbiased Base62 code generator
enum InviteCode {
    /// Generates a cryptographically random Base62 code (uniform, no modulo bias).
    /// You can safely lower the default length to 8 to shorten URLs.
    static func generate(length: Int = 8) -> String {
        let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
        var out = ""
        out.reserveCapacity(length)

        // Rejection sampling to avoid bias (62 * 4 = 248 is the largest multiple of 62 under 256)
        while out.count < length {
            var byte: UInt8 = 0
            let rc = SecRandomCopyBytes(kSecRandomDefault, 1, &byte)
            precondition(rc == errSecSuccess, "SecRandomCopyBytes failed")
            if byte < 248 {
                out.append(alphabet[Int(byte % 62)])
            }
        }
        return out
    }
}

// MARK: - Compact slug composer (binary → base64url), same public API as before
enum InviteSlugComposer {
    // Envelope layout (big-endian lengths):
    // [0]      : version (UInt8)   == 1
    // [1]      : flags   (UInt8)   bit0 => creator is Ethereum address (20B)
    // [2]      : codePackedLen (UInt8)
    // [..]     : codePacked bytes (packed Base62 -> raw)
    // [..]     : creator:
    //            if ETH flag set: exactly 20 bytes
    //            else: [len:UInt8] + UTF-8 bytes
    // [..]     : signature (65 bytes, r||s||v)
    private static let version: UInt8 = 1
    private static let flagCreatorIsEth: UInt8 = 0b0000_0001

    // === Public API (unchanged signatures) ===

    static func slug(for signedInvite: SignedInvite) throws -> String {
        let data = try pack(signedInvite)
        return b64urlEncode(data)
    }

    static func decode(_ slug: String) throws -> SignedInvite {
        guard let data = b64urlDecode(slug) else { throw URLError(.cannotDecodeContentData) }
        return try unpack(data)
    }

    static func parseURL(_ url: URL) throws -> SignedInvite {
        try decode(url.lastPathComponent)
    }

    // === Packing ===

    private static func pack(_ signed: SignedInvite) throws -> Data {
        var out = Data()
        out.append(version)

        // Decide how to encode creatorInboxId
        let creator = signed.payload.creatorInboxId
        var flags: UInt8 = 0
        let creatorBytes: Data
        if let eth = try? decodeEthereumAddress(creator) {
            flags |= flagCreatorIsEth
            creatorBytes = eth // 20 bytes
        } else {
            let utf8 = Data(creator.utf8)
            guard utf8.count <= 255 else { throw SlugError.tooLong }
            creatorBytes = utf8
        }
        out.append(flags)

        // Pack Base62 code into raw bytes (saves ~2 bytes vs UTF-8 for 8–10 char codes)
        let codePacked = try packBase62(signed.payload.code)
        guard codePacked.count <= 255 else { throw SlugError.tooLong }
        out.append(UInt8(codePacked.count))
        out.append(codePacked)

        // Creator
        if (flags & flagCreatorIsEth) != 0 {
            precondition(creatorBytes.count == 20)
            out.append(creatorBytes)
        } else {
            out.append(UInt8(creatorBytes.count))
            out.append(creatorBytes)
        }

        // Signature
        guard signed.signature.count == 65 else { throw SlugError.invalidSignatureLength }
        out.append(signed.signature)

        return out
    }

    // === Unpacking ===

    private static func unpack(_ data: Data) throws -> SignedInvite {
        var r = Reader(data)

        let ver = try r.byte()
        guard ver == version else { throw SlugError.unsupportedVersion(ver) }

        let flags = try r.byte()

        // Code
        let codeLen = Int(try r.byte())
        let codePacked = try r.bytes(count: codeLen)
        let code = try unpackBase62(codePacked)

        // Creator
        let creatorInboxId: String
        if (flags & flagCreatorIsEth) != 0 {
            let addr = try r.bytes(count: 20)
            creatorInboxId = "0x" + addr.map { String(format: "%02x", $0) }.joined()
        } else {
            let clen = Int(try r.byte())
            let cbytes = try r.bytes(count: clen)
            guard let s = String(data: cbytes, encoding: .utf8) else { throw SlugError.truncated }
            creatorInboxId = s
        }

        // Signature
        let sig = try r.bytes(count: 65)

        let payload = InvitePayload(code: code, creatorInboxId: creatorInboxId)
        return SignedInvite(payload: payload, signature: sig)
    }

    // === Helpers ===

    private enum SlugError: Error {
        case truncated
        case unsupportedVersion(UInt8)
        case invalidSignatureLength
        case invalidBase62
        case invalidHex
        case tooLong
    }

    // Base64URL (no padding)
    private static func b64urlEncode(_ d: Data) -> String {
        d.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func b64urlDecode(_ s: String) -> Data? {
        var t = s.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let pad = 4 - (t.count % 4)
        if pad < 4 { t += String(repeating: "=", count: pad) }
        return Data(base64Encoded: t)
    }

    // Detect & decode "0x" + 40 hex chars → 20 bytes
    private static func decodeEthereumAddress(_ s: String) throws -> Data {
        guard s.count == 42, s.hasPrefix("0x") else { throw SlugError.invalidHex }
        let hex = s.dropFirst(2)
        var out = Data(); out.reserveCapacity(20)
        var i = hex.startIndex
        while i < hex.endIndex {
            let j = hex.index(i, offsetBy: 2)
            guard j <= hex.endIndex, let b = UInt8(hex[i..<j], radix: 16) else { throw SlugError.invalidHex }
            out.append(b)
            i = j
        }
        guard out.count == 20 else { throw SlugError.invalidHex }
        return out
    }

    // Pack a Base62 string to minimal big-endian bytes
    private static func packBase62(_ s: String) throws -> Data {
        var value = BigInt.zero
        for ch in s {
            guard let digit = Base62.map[ch] else { throw SlugError.invalidBase62 }
            value = value * 62 + digit
        }
        return value.toMinimalBytesBE()
    }

    // Unpack minimal big-endian bytes to Base62 string
    private static func unpackBase62(_ data: Data) throws -> String {
        if data.isEmpty { return "0" }
        var x = BigInt.fromBytesBE(data)
        if x.isZero { return "0" }

        var out: [Character] = []
        while !x.isZero {
            let (q, r) = x.quotientAndRemainder(dividingBy: 62)
            out.append(Base62.chars[Int(r)])
            x = q
        }
        return String(out.reversed())
    }

    // Minimal big integer (unsigned) for packing/unpacking base62
    private struct BigInt: Equatable {
        static func += (lhs: inout Self, rhs: Self) { lhs = lhs + rhs }
        static func += (lhs: inout Self, rhs: Int) { lhs = lhs + rhs }
        static func *= (lhs: inout Self, rhs: Int) { lhs = lhs * rhs }

        // little-endian limbs base 2^32 for simplicity
        private var limbs: [UInt32] = []
        static let zero: BigInt = BigInt()

        var isZero: Bool { limbs.isEmpty }

        static func fromBytesBE(_ data: Data) -> BigInt {
            if data.isEmpty { return .zero }
            var x = BigInt()
            var i = 0
            let bytes = [UInt8](data)
            while i < bytes.count {
                let rem = bytes.count - i
                let take = min(4, rem)
                var limb: UInt32 = 0
                for j in 0..<take {
                    limb = (limb << 8) | UInt32(bytes[i + j])
                }
                x = x << (8 * take)
                x += BigInt(UInt64(limb))
                i += take
            }
            return x
        }

        func toMinimalBytesBE() -> Data {
            if limbs.isEmpty { return Data([0]) }
            // convert to bytes big-endian
            var tmp = self
            var out = Data()
            while !tmp.isZero {
                let (q, r) = tmp.divModUInt8(256)
                out.insert(UInt8(r), at: 0)
                tmp = q
            }
            // strip leading zero
            if out.count > 1, out.first == 0 { out.removeFirst() }
            return out
        }

        init() {}
        init(_ v: UInt64) {
            if v == 0 {
                limbs = []
            } else {
                limbs = [UInt32(v & 0xffff_ffff), UInt32(v >> 32)]
                while limbs.last == 0 { limbs.removeLast() }
            }
        }

        static func + (lhs: BigInt, rhs: BigInt) -> BigInt {
            var a = lhs.limbs, b = rhs.limbs
            if a.count < b.count { swap(&a, &b) }
            var carry: UInt64 = 0
            for i in 0..<a.count {
                let ai = UInt64(a[i])
                let bi = i < b.count ? UInt64(b[i]) : 0
                let sum = ai + bi + carry
                a[i] = UInt32(sum & 0xffff_ffff)
                carry = sum >> 32
            }
            if carry > 0 { a.append(UInt32(carry)) }
            var r = BigInt(); r.limbs = a; r.trim(); return r
        }

        static func * (lhs: BigInt, rhs: Int) -> BigInt {
            var a = lhs.limbs
            var carry: UInt64 = 0
            for i in 0..<a.count {
                let prod = UInt64(a[i]) * UInt64(rhs) + carry
                a[i] = UInt32(prod & 0xffff_ffff)
                carry = prod >> 32
            }
            if carry > 0 { a.append(UInt32(carry)) }
            var r = BigInt(); r.limbs = a; r.trim(); return r
        }

        static func + (lhs: BigInt, rhs: Int) -> BigInt { lhs + BigInt(UInt64(rhs)) }

        // left shift by k bits
        static func << (lhs: BigInt, rhs: Int) -> BigInt {
            guard rhs > 0, !lhs.isZero else { return lhs }
            let limbShift = rhs / 32
            let bitShift = rhs % 32
            var res = [UInt32](repeating: 0, count: lhs.limbs.count + limbShift + 1)
            var carry: UInt64 = 0
            for (i, limb) in lhs.limbs.enumerated() {
                let v = (UInt64(limb) << bitShift) | carry
                res[i + limbShift] = UInt32(v & 0xffff_ffff)
                carry = v >> 32
            }
            if carry > 0 { res[lhs.limbs.count + limbShift] = UInt32(carry) }
            var r = BigInt(); r.limbs = res; r.trim(); return r
        }

        // division by small UInt8, returns (quotient, remainder)
        func quotientAndRemainder(dividingBy d: Int) -> (BigInt, Int) {
            var q = [UInt32](repeating: 0, count: limbs.count)
            var rem: UInt64 = 0
            for i in stride(from: limbs.count - 1, through: 0, by: -1) {
                let cur = (rem << 32) | UInt64(limbs[i])
                let qq = cur / UInt64(d)
                rem = cur % UInt64(d)
                q[i] = UInt32(qq)
            }
            var r = BigInt(); r.limbs = q; r.trim()
            return (r, Int(rem))
        }

        private func divModUInt8(_ d: Int) -> (BigInt, Int) { quotientAndRemainder(dividingBy: d) }

        private mutating func trim() {
            while limbs.last == 0 { limbs.removeLast() }
        }
    }

    // Simple reader
    private struct Reader {
        private let data: Data
        private var offset: Int = 0
        init(_ d: Data) { self.data = d }

        mutating func byte() throws -> UInt8 {
            guard offset + 1 <= data.count else { throw SlugError.truncated }
            defer { offset += 1 }
            return data[offset]
        }

        mutating func bytes(count: Int) throws -> Data {
            guard offset + count <= data.count else { throw SlugError.truncated }
            let d = data.subdata(in: offset ..< offset + count)
            offset += count
            return d
        }
    }

    private enum Base62 {
        static let chars: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
        static let map: [Character: Int] = {
            var d: [Character: Int] = [:]
            d.reserveCapacity(chars.count)
            for (i, c) in chars.enumerated() { d[c] = i }
            return d
        }()
    }
}
