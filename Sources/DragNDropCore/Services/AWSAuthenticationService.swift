import Foundation
import Logging
import AWSClientRuntime
import AWSSSO
import AWSSSOOIDC
import AWSSTS
import SmithyIdentity
import SmithyIdentityAPI

// MARK: - AWS Authentication Service

/// Manages AWS authentication including SSO login
public final class AWSAuthenticationService: @unchecked Sendable {
    private let logger = Logger(label: "com.dragndrop.aws.auth")

    private var currentCredentials: AWSCredentials?
    private var ssoClient: SSOClient?
    private var ssoOIDCClient: SSOOIDCClient?
    private let lock = NSLock()

    // SSO session state
    private var deviceCode: String?
    private var clientId: String?
    private var clientSecret: String?

    public init() {}

    // MARK: - Public Interface

    /// Current authentication state
    public var authenticationState: AuthenticationState {
        guard let creds = currentCredentials else {
            return .notAuthenticated
        }

        if creds.isExpired {
            return .expired
        }

        return .authenticated(creds)
    }

    /// Check if currently authenticated with valid credentials
    public var isAuthenticated: Bool {
        authenticationState.isAuthenticated
    }

    /// Get current credentials if valid
    public var credentials: AWSCredentials? {
        guard let creds = currentCredentials, !creds.isExpired else {
            return nil
        }
        return creds
    }

    // MARK: - SSO Authentication

    /// Initiates SSO login flow
    /// Returns the verification URL and user code for the user to complete login
    public func initiateSSOLogin(
        startURL: String,
        region: String
    ) async throws -> SSOLoginInfo {
        logger.info("Initiating SSO login for \(startURL) in \(region)")

        // Create SSO OIDC client
        let config = try await SSOOIDCClient.SSOOIDCClientConfiguration(region: region)
        ssoOIDCClient = SSOOIDCClient(config: config)

        guard let oidcClient = ssoOIDCClient else {
            throw AWSAuthError.clientInitFailed
        }

        // Register client
        let registerInput = RegisterClientInput(
            clientName: "dragndrop",
            clientType: "public",
            scopes: ["sso:account:access"]
        )

        let registerOutput = try await oidcClient.registerClient(input: registerInput)

        guard let clientId = registerOutput.clientId,
              let clientSecret = registerOutput.clientSecret else {
            throw AWSAuthError.registrationFailed
        }

        self.clientId = clientId
        self.clientSecret = clientSecret

        // Start device authorization
        let authInput = StartDeviceAuthorizationInput(
            clientId: clientId,
            clientSecret: clientSecret,
            startUrl: startURL
        )

        let authOutput = try await oidcClient.startDeviceAuthorization(input: authInput)

        guard let deviceCode = authOutput.deviceCode,
              let userCode = authOutput.userCode,
              let verificationUri = authOutput.verificationUri else {
            throw AWSAuthError.deviceAuthFailed
        }

        self.deviceCode = deviceCode

        let verificationUriComplete = authOutput.verificationUriComplete ?? verificationUri

        return SSOLoginInfo(
            verificationUri: verificationUri,
            verificationUriComplete: verificationUriComplete,
            userCode: userCode,
            deviceCode: deviceCode,
            expiresIn: Int(authOutput.expiresIn),
            interval: Int(authOutput.interval ?? 5)
        )
    }

    /// Polls for SSO token after user completes browser authentication
    public func pollForSSOToken(interval: Int = 5, timeout: Int = 300) async throws -> String {
        guard let oidcClient = ssoOIDCClient,
              let clientId = clientId,
              let clientSecret = clientSecret,
              let deviceCode = deviceCode else {
            throw AWSAuthError.notInitialized
        }

        let startTime = Date()
        let timeoutDate = startTime.addingTimeInterval(TimeInterval(timeout))

        while Date() < timeoutDate {
            do {
                let tokenInput = CreateTokenInput(
                    clientId: clientId,
                    clientSecret: clientSecret,
                    deviceCode: deviceCode,
                    grantType: "urn:ietf:params:oauth:grant-type:device_code"
                )

                let tokenOutput = try await oidcClient.createToken(input: tokenInput)

                if let accessToken = tokenOutput.accessToken {
                    logger.info("SSO token obtained successfully")
                    return accessToken
                }
            } catch let error as AuthorizationPendingException {
                // User hasn't completed authorization yet, keep polling
                logger.debug("Authorization pending, continuing to poll...")
            } catch let error as SlowDownException {
                // Slow down polling
                try await Task.sleep(nanoseconds: UInt64((interval + 5) * 1_000_000_000))
                continue
            } catch {
                // Check if it's an authorization pending error by error code
                let errorDescription = String(describing: error)
                if errorDescription.contains("AuthorizationPending") ||
                   errorDescription.contains("authorization_pending") {
                    logger.debug("Authorization pending, continuing to poll...")
                } else if errorDescription.contains("SlowDown") ||
                          errorDescription.contains("slow_down") {
                    try await Task.sleep(nanoseconds: UInt64((interval + 5) * 1_000_000_000))
                    continue
                } else {
                    throw error
                }
            }

            try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }

        throw AWSAuthError.timeout
    }

    /// Gets credentials using SSO access token
    public func getCredentialsFromSSO(
        accessToken: String,
        accountId: String,
        roleName: String,
        region: String
    ) async throws -> AWSCredentials {
        logger.info("Getting credentials for account \(accountId), role \(roleName)")

        let config = try await SSOClient.SSOClientConfiguration(region: region)
        ssoClient = SSOClient(config: config)

        guard let client = ssoClient else {
            throw AWSAuthError.clientInitFailed
        }

        let input = GetRoleCredentialsInput(
            accessToken: accessToken,
            accountId: accountId,
            roleName: roleName
        )

        let output = try await client.getRoleCredentials(input: input)

        guard let creds = output.roleCredentials,
              let accessKeyId = creds.accessKeyId,
              let secretAccessKey = creds.secretAccessKey else {
            throw AWSAuthError.credentialsFailed
        }

        let expirationDate: Date?
        if creds.expiration != 0 {
            expirationDate = Date(timeIntervalSince1970: TimeInterval(creds.expiration / 1000))
        } else {
            expirationDate = nil
        }

        let credentials = AWSCredentials(
            accessKeyId: accessKeyId,
            secretAccessKey: secretAccessKey,
            sessionToken: creds.sessionToken,
            expiration: expirationDate
        )

        self.currentCredentials = credentials
        logger.info("Credentials obtained, expires: \(credentials.expiration?.description ?? "unknown")")

        return credentials
    }

    // MARK: - Profile-based Authentication

    /// Loads credentials from AWS CLI profile
    public func loadFromProfile(profileName: String = "default") async throws -> AWSCredentials {
        logger.info("Loading credentials from profile: \(profileName)")

        // Try to load from credentials file
        let credentialsPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".aws/credentials")

        if let content = try? String(contentsOf: credentialsPath, encoding: .utf8) {
            if let creds = parseCredentialsFile(content: content, profile: profileName) {
                self.currentCredentials = creds
                return creds
            }
        }

        // Try SSO credential cache
        let cachePath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".aws/sso/cache")

        if let cacheFiles = try? FileManager.default.contentsOfDirectory(atPath: cachePath.path) {
            for file in cacheFiles where file.hasSuffix(".json") {
                let filePath = cachePath.appendingPathComponent(file)
                if let data = try? Data(contentsOf: filePath),
                   let cache = try? JSONDecoder().decode(SSOCacheEntry.self, from: data) {
                    if let accessToken = cache.accessToken,
                       let expiry = cache.expiresAt,
                       expiry > Date() {
                        // Load config for account/role
                        if let config = loadSSOConfig(profileName: profileName) {
                            return try await getCredentialsFromSSO(
                                accessToken: accessToken,
                                accountId: config.accountId,
                                roleName: config.roleName,
                                region: config.region
                            )
                        }
                    }
                }
            }
        }

        throw AWSAuthError.profileNotFound(profileName)
    }

    /// Refreshes credentials if expired or about to expire
    public func refreshIfNeeded() async throws {
        guard let creds = currentCredentials else {
            throw AWSAuthError.notAuthenticated
        }

        // Refresh if expiring within 5 minutes
        if let expiration = creds.expiration,
           expiration.timeIntervalSinceNow < 300 {
            logger.info("Credentials expiring soon, attempting refresh")
            // Attempt to reload from profile
            _ = try await loadFromProfile()
        }
    }

    /// Signs out and clears credentials
    public func signOut() {
        currentCredentials = nil
        deviceCode = nil
        clientId = nil
        clientSecret = nil
        ssoClient = nil
        ssoOIDCClient = nil
        logger.info("Signed out")
    }

    /// Sets credentials directly (for access key/secret key authentication)
    public func setDirectCredentials(_ credentials: AWSCredentials, region: String) {
        currentCredentials = credentials
        logger.info("Direct credentials set for region: \(region)")
    }

    // MARK: - Helpers

    private func parseCredentialsFile(content: String, profile: String) -> AWSCredentials? {
        let lines = content.components(separatedBy: .newlines)
        var inProfile = false
        var accessKey: String?
        var secretKey: String?
        var sessionToken: String?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                let profileName = String(trimmed.dropFirst().dropLast())
                inProfile = (profileName == profile)
                continue
            }

            if inProfile {
                let parts = trimmed.components(separatedBy: "=").map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count == 2 {
                    switch parts[0].lowercased() {
                    case "aws_access_key_id":
                        accessKey = parts[1]
                    case "aws_secret_access_key":
                        secretKey = parts[1]
                    case "aws_session_token":
                        sessionToken = parts[1]
                    default:
                        break
                    }
                }
            }
        }

        guard let ak = accessKey, let sk = secretKey else {
            return nil
        }

        return AWSCredentials(
            accessKeyId: ak,
            secretAccessKey: sk,
            sessionToken: sessionToken
        )
    }

    private func loadSSOConfig(profileName: String) -> SSOConfigEntry? {
        let configPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".aws/config")

        guard let content = try? String(contentsOf: configPath, encoding: .utf8) else {
            return nil
        }

        let lines = content.components(separatedBy: .newlines)
        var inProfile = false
        var accountId: String?
        var roleName: String?
        var region: String?
        var startUrl: String?

        let targetProfile = profileName == "default" ? "default" : "profile \(profileName)"

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                let sectionName = String(trimmed.dropFirst().dropLast())
                inProfile = (sectionName == targetProfile)
                continue
            }

            if inProfile {
                let parts = trimmed.components(separatedBy: "=").map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count == 2 {
                    switch parts[0] {
                    case "sso_account_id":
                        accountId = parts[1]
                    case "sso_role_name":
                        roleName = parts[1]
                    case "sso_region", "region":
                        region = parts[1]
                    case "sso_start_url":
                        startUrl = parts[1]
                    default:
                        break
                    }
                }
            }
        }

        guard let aid = accountId, let rn = roleName, let r = region else {
            return nil
        }

        return SSOConfigEntry(
            accountId: aid,
            roleName: rn,
            region: r,
            startUrl: startUrl
        )
    }

    // MARK: - AWS STS Operations

    /// Gets the current caller identity
    public func getCallerIdentity() async throws -> CallerIdentity {
        guard let creds = credentials else {
            throw AWSAuthError.notAuthenticated
        }

        let identity = AWSCredentialIdentity(
            accessKey: creds.accessKeyId,
            secret: creds.secretAccessKey,
            sessionToken: creds.sessionToken
        )

        let staticCreds = try StaticAWSCredentialIdentityResolver(identity)

        let config = try await STSClient.STSClientConfiguration(
            awsCredentialIdentityResolver: staticCreds,
            region: "us-east-1"
        )
        let client = STSClient(config: config)

        let output = try await client.getCallerIdentity(input: GetCallerIdentityInput())

        return CallerIdentity(
            account: output.account ?? "Unknown",
            arn: output.arn ?? "Unknown",
            userId: output.userId ?? "Unknown"
        )
    }
}

// MARK: - Supporting Types

public struct SSOLoginInfo: Sendable {
    public let verificationUri: String
    public let verificationUriComplete: String
    public let userCode: String
    public let deviceCode: String
    public let expiresIn: Int
    public let interval: Int
}

public struct CallerIdentity: Sendable {
    public let account: String
    public let arn: String
    public let userId: String
}

private struct SSOCacheEntry: Codable {
    let accessToken: String?
    let expiresAt: Date?
    let region: String?
    let startUrl: String?

    enum CodingKeys: String, CodingKey {
        case accessToken
        case expiresAt
        case region
        case startUrl
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try container.decodeIfPresent(String.self, forKey: .accessToken)
        region = try container.decodeIfPresent(String.self, forKey: .region)
        startUrl = try container.decodeIfPresent(String.self, forKey: .startUrl)

        if let dateString = try container.decodeIfPresent(String.self, forKey: .expiresAt) {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            expiresAt = formatter.date(from: dateString)
        } else {
            expiresAt = nil
        }
    }
}

private struct SSOConfigEntry {
    let accountId: String
    let roleName: String
    let region: String
    let startUrl: String?
}

// MARK: - Errors

public enum AWSAuthError: Error, LocalizedError {
    case clientInitFailed
    case registrationFailed
    case deviceAuthFailed
    case notInitialized
    case timeout
    case credentialsFailed
    case profileNotFound(String)
    case notAuthenticated

    public var errorDescription: String? {
        switch self {
        case .clientInitFailed:
            return "Failed to initialize AWS client"
        case .registrationFailed:
            return "SSO client registration failed"
        case .deviceAuthFailed:
            return "Device authorization failed"
        case .notInitialized:
            return "SSO session not initialized"
        case .timeout:
            return "SSO login timed out"
        case .credentialsFailed:
            return "Failed to obtain credentials"
        case .profileNotFound(let name):
            return "AWS profile '\(name)' not found"
        case .notAuthenticated:
            return "Not authenticated"
        }
    }
}
