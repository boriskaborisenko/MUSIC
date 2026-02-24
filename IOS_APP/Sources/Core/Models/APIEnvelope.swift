import Foundation

struct ServerEnvelope<T: Decodable>: Decodable {
  let ok: Bool
  let data: T
  let error: ServerErrorPayload?
  let ts: String?
}

struct ServerFailureEnvelope: Decodable {
  let ok: Bool
  let error: ServerErrorPayload?
  let ts: String?
}

struct ServerErrorPayload: Decodable {
  let code: String?
  let message: String?
}

