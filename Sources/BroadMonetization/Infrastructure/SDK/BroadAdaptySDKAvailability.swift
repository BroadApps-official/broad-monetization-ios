#if canImport(Adapty)
    import Adapty
#endif

public enum BroadAdaptySDKAvailability {
    public static var isLinked: Bool {
        #if canImport(Adapty)
            true
        #else
            false
        #endif
    }
}
