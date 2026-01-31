import Foundation
import CommonCrypto

// MARK: - S3 Presign Service

/// Generates presigned URLs for S3 objects using AWS Signature Version 4
public final class S3PresignService: @unchecked Sendable {
    private let lock = NSLock()
    private var credentials: AWSCredentials?
    private var region: String = "us-east-1"

    public init() {}

    // MARK: - Configuration

    public func configure(credentials: AWSCredentials, region: String) {
        lock.lock()
        defer { lock.unlock() }
        self.credentials = credentials
        self.region = region
    }

    // MARK: - Presigned URL Generation

    /// Generates a presigned URL for downloading an S3 object
    public func presignGetObject(
        bucket: String,
        key: String,
        expiresIn: Int = 3600
    ) throws -> URL {
        lock.lock()
        let creds = credentials
        let region = self.region
        lock.unlock()

        guard let credentials = creds else {
            throw PresignError.noCredentials
        }

        let now = Date()
        let expiration = expiresIn

        // Build the canonical request components
        let host = "\(bucket).s3.\(region).amazonaws.com"
        let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? key
        let path = "/\(encodedKey)"

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        let amzDate = dateFormatter.string(from: now)

        dateFormatter.dateFormat = "yyyyMMdd"
        let dateStamp = dateFormatter.string(from: now)

        let credentialScope = "\(dateStamp)/\(region)/s3/aws4_request"
        let credential = "\(credentials.accessKeyId)/\(credentialScope)"

        // Build query string parameters (alphabetically sorted)
        var queryParams: [(String, String)] = [
            ("X-Amz-Algorithm", "AWS4-HMAC-SHA256"),
            ("X-Amz-Credential", credential),
            ("X-Amz-Date", amzDate),
            ("X-Amz-Expires", String(expiration)),
            ("X-Amz-SignedHeaders", "host"),
        ]

        if let sessionToken = credentials.sessionToken {
            queryParams.append(("X-Amz-Security-Token", sessionToken))
        }

        queryParams.sort { $0.0 < $1.0 }

        let canonicalQueryString = queryParams
            .map { "\(urlEncode($0.0))=\(urlEncode($0.1))" }
            .joined(separator: "&")

        // Canonical headers
        let canonicalHeaders = "host:\(host)\n"
        let signedHeaders = "host"

        // Create canonical request
        let canonicalRequest = [
            "GET",
            path,
            canonicalQueryString,
            canonicalHeaders,
            signedHeaders,
            "UNSIGNED-PAYLOAD"
        ].joined(separator: "\n")

        // Create string to sign
        let canonicalRequestHash = sha256Hash(canonicalRequest)
        let stringToSign = [
            "AWS4-HMAC-SHA256",
            amzDate,
            credentialScope,
            canonicalRequestHash
        ].joined(separator: "\n")

        // Calculate signature
        let signature = calculateSignature(
            stringToSign: stringToSign,
            secretKey: credentials.secretAccessKey,
            dateStamp: dateStamp,
            region: region
        )

        // Build final URL
        let finalQueryString = canonicalQueryString + "&X-Amz-Signature=\(signature)"
        let urlString = "https://\(host)\(path)?\(finalQueryString)"

        guard let url = URL(string: urlString) else {
            throw PresignError.invalidURL
        }

        return url
    }

    /// Generates a presigned URL for uploading an S3 object
    public func presignPutObject(
        bucket: String,
        key: String,
        contentType: String? = nil,
        expiresIn: Int = 3600
    ) throws -> URL {
        lock.lock()
        let creds = credentials
        let region = self.region
        lock.unlock()

        guard let credentials = creds else {
            throw PresignError.noCredentials
        }

        let now = Date()
        let expiration = expiresIn

        let host = "\(bucket).s3.\(region).amazonaws.com"
        let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? key
        let path = "/\(encodedKey)"

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        let amzDate = dateFormatter.string(from: now)

        dateFormatter.dateFormat = "yyyyMMdd"
        let dateStamp = dateFormatter.string(from: now)

        let credentialScope = "\(dateStamp)/\(region)/s3/aws4_request"
        let credential = "\(credentials.accessKeyId)/\(credentialScope)"

        var queryParams: [(String, String)] = [
            ("X-Amz-Algorithm", "AWS4-HMAC-SHA256"),
            ("X-Amz-Credential", credential),
            ("X-Amz-Date", amzDate),
            ("X-Amz-Expires", String(expiration)),
            ("X-Amz-SignedHeaders", "host"),
        ]

        if let sessionToken = credentials.sessionToken {
            queryParams.append(("X-Amz-Security-Token", sessionToken))
        }

        queryParams.sort { $0.0 < $1.0 }

        let canonicalQueryString = queryParams
            .map { "\(urlEncode($0.0))=\(urlEncode($0.1))" }
            .joined(separator: "&")

        let canonicalHeaders = "host:\(host)\n"
        let signedHeaders = "host"

        let canonicalRequest = [
            "PUT",
            path,
            canonicalQueryString,
            canonicalHeaders,
            signedHeaders,
            "UNSIGNED-PAYLOAD"
        ].joined(separator: "\n")

        let canonicalRequestHash = sha256Hash(canonicalRequest)
        let stringToSign = [
            "AWS4-HMAC-SHA256",
            amzDate,
            credentialScope,
            canonicalRequestHash
        ].joined(separator: "\n")

        let signature = calculateSignature(
            stringToSign: stringToSign,
            secretKey: credentials.secretAccessKey,
            dateStamp: dateStamp,
            region: region
        )

        let finalQueryString = canonicalQueryString + "&X-Amz-Signature=\(signature)"
        let urlString = "https://\(host)\(path)?\(finalQueryString)"

        guard let url = URL(string: urlString) else {
            throw PresignError.invalidURL
        }

        return url
    }

    // MARK: - S3 URI Helpers

    /// Converts an S3 URI to an HTTPS URL
    public func s3URIToHTTPS(s3URI: String, region: String? = nil) -> URL? {
        guard s3URI.hasPrefix("s3://") else { return nil }

        let withoutPrefix = String(s3URI.dropFirst(5))
        guard let slashIndex = withoutPrefix.firstIndex(of: "/") else { return nil }

        let bucket = String(withoutPrefix[..<slashIndex])
        let key = String(withoutPrefix[withoutPrefix.index(after: slashIndex)...])

        let r = region ?? self.region
        let urlString = "https://\(bucket).s3.\(r).amazonaws.com/\(key)"
        return URL(string: urlString)
    }

    /// Generates the AWS Console URL for an S3 object
    public func consoleURL(bucket: String, key: String, region: String? = nil) -> URL? {
        let r = region ?? self.region
        let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
        let urlString = "https://\(r).console.aws.amazon.com/s3/object/\(bucket)?region=\(r)&prefix=\(encodedKey)"
        return URL(string: urlString)
    }

    // MARK: - Signing Helpers

    private func sha256Hash(_ string: String) -> String {
        let data = Data(string.utf8)
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    private func hmacSHA256(key: Data, data: String) -> Data {
        let dataBytes = Data(data.utf8)
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))

        key.withUnsafeBytes { keyPtr in
            dataBytes.withUnsafeBytes { dataPtr in
                CCHmac(
                    CCHmacAlgorithm(kCCHmacAlgSHA256),
                    keyPtr.baseAddress,
                    key.count,
                    dataPtr.baseAddress,
                    dataBytes.count,
                    &hash
                )
            }
        }

        return Data(hash)
    }

    private func calculateSignature(
        stringToSign: String,
        secretKey: String,
        dateStamp: String,
        region: String
    ) -> String {
        let kSecret = Data("AWS4\(secretKey)".utf8)
        let kDate = hmacSHA256(key: kSecret, data: dateStamp)
        let kRegion = hmacSHA256(key: kDate, data: region)
        let kService = hmacSHA256(key: kRegion, data: "s3")
        let kSigning = hmacSHA256(key: kService, data: "aws4_request")
        let signature = hmacSHA256(key: kSigning, data: stringToSign)

        return signature.map { String(format: "%02x", $0) }.joined()
    }

    private func urlEncode(_ string: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }
}

// MARK: - Errors

public enum PresignError: Error, LocalizedError {
    case noCredentials
    case invalidURL

    public var errorDescription: String? {
        switch self {
        case .noCredentials:
            return "No AWS credentials configured"
        case .invalidURL:
            return "Failed to construct presigned URL"
        }
    }
}
