// Sous Linux, URLRequest/HTTPURLResponse vivent dans FoundationNetworking ; on le réexporte pour
// que les modules et tests qui importent HindsightAPI compilent à l'identique sur macOS et Linux.
#if canImport(FoundationNetworking)
@_exported import FoundationNetworking
#endif
