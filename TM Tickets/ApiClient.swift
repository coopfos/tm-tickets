import Foundation
import UniformTypeIdentifiers

struct DraftResponse: Decodable {
    let id: String
    let savedAt: String
}

enum ApiError: Error, LocalizedError {
    case notConfigured
    case requestFailed(Int)
    case invalidResponse
    case underlying(Error)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "API base URL not configured."
        case .requestFailed(let code): return "Request failed with status code \(code)."
        case .invalidResponse: return "Invalid response from server."
        case .underlying(let err): return err.localizedDescription
        }
    }
}

struct DraftPayload: Encodable {
    var id: String? = nil
    let jobNumber: String
    let jobName: String
    let date: String // ISO8601
    let customerName: String
    let technician: String
    let workPerformed: String
    let materialList: String
    let labor: [LaborDTO]
}

struct LaborDTO: Codable {
    let role: String
    let regularHours: Double
    let otHours: Double
}

final class ApiClient {
    struct NextNumberResponse: Decodable { let ticketNumber: String }

    struct DraftDocument: Decodable {
        let id: String
        let jobNumber: String
        let jobName: String
        let date: String
        let customerName: String
        let technician: String
        let workPerformed: String
        let materialList: String
        let labor: [LaborDTO]
    }
    struct DraftListItem: Decodable {
        let id: String
        let jobNumber: String
        let jobName: String?
        let date: String
    }

    // Compute robust API URL: avoids duplicating "/api" if user added it.
    static func draftEndpointURL(from base: URL) -> URL {
        var url = base
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let hasApi = path.lowercased().split(separator: "/").last == "api"
        if !hasApi { url.appendPathComponent("api", conformingTo: .url) }
        url.appendPathComponent("tickets", conformingTo: .url)
        url.appendPathComponent("draft", conformingTo: .url)
        return url
    }

    // Simple health endpoint on classic app (GET /api/hello)
    static func helloEndpointURL(from base: URL) -> URL {
        var url = base
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let hasApi = path.lowercased().split(separator: "/").last == "api"
        if !hasApi { url.appendPathComponent("api", conformingTo: .url) }
        url.appendPathComponent("hello", conformingTo: .url)
        return url
    }

    static func draftGetURL(from base: URL, id: String) -> URL {
        var url = base
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let hasApi = path.lowercased().split(separator: "/").last == "api"
        if !hasApi { url.appendPathComponent("api", conformingTo: .url) }
        url.appendPathComponent("tickets", conformingTo: .url)
        url.appendPathComponent("draft", conformingTo: .url)
        url.appendPathComponent(id, conformingTo: .url)
        return url
    }
    static func draftListURL(from base: URL, jobNumber: String) -> URL {
        var url = base
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let hasApi = path.lowercased().split(separator: "/").last == "api"
        if !hasApi { url.appendPathComponent("api", conformingTo: .url) }
        url.appendPathComponent("tickets", conformingTo: .url)
        url.appendPathComponent("draft", conformingTo: .url)
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "jobNumber", value: jobNumber)]
        return comps.url ?? url
    }

    static func nextNumberURL(from base: URL) -> URL {
        var url = base
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let hasApi = path.lowercased().split(separator: "/").last == "api"
        if !hasApi { url.appendPathComponent("api", conformingTo: .url) }
        url.appendPathComponent("tickets", conformingTo: .url)
        url.appendPathComponent("next-number", conformingTo: .url)
        return url
    }

    static func jobLookupURL(from base: URL, jobNumber: String) -> URL {
        var url = base
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let hasApi = path.lowercased().split(separator: "/").last == "api"
        if !hasApi { url.appendPathComponent("api", conformingTo: .url) }
        url.appendPathComponent("reference", conformingTo: .url)
        url.appendPathComponent("job-numbers", conformingTo: .url)
        url.appendPathComponent(jobNumber, conformingTo: .url)
        return url
    }

    static func jobListURL(from base: URL, prefix: String?) -> URL {
        var url = base
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let hasApi = path.lowercased().split(separator: "/").last == "api"
        if !hasApi { url.appendPathComponent("api", conformingTo: .url) }
        url.appendPathComponent("reference", conformingTo: .url)
        url.appendPathComponent("job-numbers", conformingTo: .url)
        if let prefix = prefix, !prefix.isEmpty, var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            comps.queryItems = [URLQueryItem(name: "prefix", value: prefix)]
            return comps.url ?? url
        }
        return url
    }

    static func techListURL(from base: URL, prefix: String?) -> URL {
        var url = base
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let hasApi = path.lowercased().split(separator: "/").last == "api"
        if !hasApi { url.appendPathComponent("api", conformingTo: .url) }
        url.appendPathComponent("reference", conformingTo: .url)
        url.appendPathComponent("technicians", conformingTo: .url)
        if let prefix = prefix, !prefix.isEmpty, var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            comps.queryItems = [URLQueryItem(name: "prefix", value: prefix)]
            return comps.url ?? url
        }
        return url
    }

    func getNextTicketNumber() async throws -> String {
        guard let base = AppConfig.apiBaseURL else { throw ApiError.notConfigured }
        let url = ApiClient.nextNumberURL(from: base)
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        if let token = AppConfig.bearerToken { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { throw ApiError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else { throw ApiError.requestFailed(http.statusCode) }
            let res = try JSONDecoder().decode(NextNumberResponse.self, from: data)
            return res.ticketNumber
        } catch {
            if let apiErr = error as? ApiError { throw apiErr }
            throw ApiError.underlying(error)
        }
    }

    struct JobEntity: Decodable {
        let PartitionKey: String?
        let RowKey: String?
        let Description: String?
        let CustomerName: String?
        let Status: String?
        // Support both new and legacy field names from the API
        let projectManager: String?
        let pmName: String?
    }

    struct JobInfo { let name: String; let customerName: String; let projectManager: String }

    func getJobInfo(for jobNumber: String) async throws -> JobInfo? {
        guard let base = AppConfig.apiBaseURL else { throw ApiError.notConfigured }
        let url = ApiClient.jobLookupURL(from: base, jobNumber: jobNumber)
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        if let token = AppConfig.bearerToken { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        do {
            #if DEBUG
            print("Job lookup URL: \(url.absoluteString)")
            #endif
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { throw ApiError.invalidResponse }
            #if DEBUG
            print("Job lookup status: \(http.statusCode)")
            #endif
            if http.statusCode == 404 { return nil }
            guard (200..<300).contains(http.statusCode) else { throw ApiError.requestFailed(http.statusCode) }
            let entity = try JSONDecoder().decode(JobEntity.self, from: data)
            let pm = entity.projectManager ?? entity.pmName ?? ""
            if let name = entity.Description, let customer = entity.CustomerName {
                #if DEBUG
                print("Decoded JobEntity projectManager=\(pm)")
                #endif
                return JobInfo(name: name, customerName: customer, projectManager: pm)
            }
            if let name = entity.Description {
                #if DEBUG
                print("Decoded JobEntity projectManager=\(pm)")
                #endif
                return JobInfo(name: name, customerName: "", projectManager: pm)
            }
            return nil
        } catch {
            if let apiErr = error as? ApiError { throw apiErr }
            throw ApiError.underlying(error)
        }
    }

    struct JobListResponse: Decodable { let items: [JobItem] }
    struct JobItem: Decodable {
        let RowKey: String
        let JobNumber: String?
        let Description: String?
        let CustomerName: String?
        var displayJobNumber: String { JobNumber ?? RowKey }
    }

    func listJobs(prefix: String?) async throws -> [JobItem] {
        guard let base = AppConfig.apiBaseURL else { throw ApiError.notConfigured }
        let url = ApiClient.jobListURL(from: base, prefix: prefix)
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        if let token = AppConfig.bearerToken { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        do {
            #if DEBUG
            print("Job list URL: \(url.absoluteString)")
            #endif
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { throw ApiError.invalidResponse }
            #if DEBUG
            if !(200..<300).contains(http.statusCode) {
                let body = String(data: data, encoding: .utf8) ?? ""
                print("Job list failed (\(http.statusCode)): \(body)")
            } else {
                print("Job list status: \(http.statusCode)")
            }
            #endif
            guard (200..<300).contains(http.statusCode) else { throw ApiError.requestFailed(http.statusCode) }
            let res = try JSONDecoder().decode(JobListResponse.self, from: data)
            return res.items
        } catch {
            if let apiErr = error as? ApiError { throw apiErr }
            throw ApiError.underlying(error)
        }
    }

    struct TechnicianItem: Decodable {
        let RowKey: String
        let TechName: String?
        var displayName: String { TechName ?? RowKey }
    }
    struct TechListResponse: Decodable { let items: [TechnicianItem] }

    func listTechnicians(prefix: String?) async throws -> [TechnicianItem] {
        guard let base = AppConfig.apiBaseURL else { throw ApiError.notConfigured }
        let url = ApiClient.techListURL(from: base, prefix: prefix)
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        if let token = AppConfig.bearerToken { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        do {
            #if DEBUG
            print("Tech list URL: \(url.absoluteString)")
            #endif
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { throw ApiError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else { throw ApiError.requestFailed(http.statusCode) }
            let res = try JSONDecoder().decode(TechListResponse.self, from: data)
            return res.items
        } catch {
            if let apiErr = error as? ApiError { throw apiErr }
            throw ApiError.underlying(error)
        }
    }

    func loadDraft(id: String) async throws -> DraftDocument {
        guard let base = AppConfig.apiBaseURL else { throw ApiError.notConfigured }
        let url = ApiClient.draftGetURL(from: base, id: id)
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        if let token = AppConfig.bearerToken { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { throw ApiError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else { throw ApiError.requestFailed(http.statusCode) }
            return try JSONDecoder().decode(DraftDocument.self, from: data)
        } catch {
            if let apiErr = error as? ApiError { throw apiErr }
            throw ApiError.underlying(error)
        }
    }

    func listDrafts(jobNumber: String) async throws -> [DraftListItem] {
        guard let base = AppConfig.apiBaseURL else { throw ApiError.notConfigured }
        let url = ApiClient.draftListURL(from: base, jobNumber: jobNumber)
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        if let token = AppConfig.bearerToken { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { throw ApiError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else { throw ApiError.requestFailed(http.statusCode) }
            struct ListResponse: Decodable { let items: [DraftListItem] }
            return try JSONDecoder().decode(ListResponse.self, from: data).items
        } catch {
            if let apiErr = error as? ApiError { throw apiErr }
            throw ApiError.underlying(error)
        }
    }

    func deleteDraft(id: String) async throws {
        guard let base = AppConfig.apiBaseURL else { throw ApiError.notConfigured }
        let url = ApiClient.draftGetURL(from: base, id: id)
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        if let token = AppConfig.bearerToken { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { throw ApiError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else { throw ApiError.requestFailed(http.statusCode) }
        } catch {
            if let apiErr = error as? ApiError { throw apiErr }
            throw ApiError.underlying(error)
        }
    }

    func saveDraft(_ payload: DraftPayload) async throws -> DraftResponse {
        guard let base = AppConfig.apiBaseURL else { throw ApiError.notConfigured }
        let url = ApiClient.draftEndpointURL(from: base)

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        // Prefer MSAL token if available, fallback to manually configured token
        if let msalToken = await AuthService.shared.getAccessTokenSilently(), !msalToken.isEmpty {
            req.setValue("Bearer \(msalToken)", forHTTPHeaderField: "Authorization")
        } else if let token = AppConfig.bearerToken, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        req.httpBody = try encoder.encode(payload)

        do {
            // DEBUG: print the outgoing URL for troubleshooting 404s
            #if DEBUG
            print("Draft POST URL: \(url.absoluteString)")
            #endif
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { throw ApiError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else {
                #if DEBUG
                if let body = String(data: data, encoding: .utf8) { print("Draft POST failed (\(http.statusCode)): \(body)") }
                #endif
                throw ApiError.requestFailed(http.statusCode)
            }
            return try JSONDecoder().decode(DraftResponse.self, from: data)
        } catch {
            if let apiErr = error as? ApiError { throw apiErr }
            throw ApiError.underlying(error)
        }
    }
}
