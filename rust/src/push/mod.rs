//! What Bosstro asks of
//! [mostro-push-server](https://github.com/MostroP2P/mostro-push-server):
//!
//! - [`wake`]: ring a party the solver wrote to (`POST /api/notify`).
//! - [`watch`]: ring this device when the active node opens a dispute
//!   (`POST /api/disputes/watch`).
//!
//! Both talk to the same server, with the same client and the same override
//! for the tests.

pub(crate) mod wake;
pub(crate) mod watch;

pub(crate) use wake::Waker;

/// The instance MostroP2P/app registers its devices with.
pub(crate) const SERVER_URL: &str = "https://mostro-push-server.fly.dev";

/// **Debug builds only:** where the requests of the end-to-end tests
/// (`integration_test/`) go, in place of [`SERVER_URL`]: a loopback server
/// (`http://127.0.0.1:<port>` or `http://localhost:<port>`), or, with any
/// other value (`off`), nowhere: no party is woken and no node is watched. Release builds never read it.
#[cfg(debug_assertions)]
pub const TEST_SERVER_ENV: &str = "BOSSTRO_TEST_PUSH_SERVER";

/// The server a value of [`TEST_SERVER_ENV`] names: a loopback one, or none.
/// A value that is not one turns the requests off rather than falling back to
/// the real server, so a typo cannot send a test's keys there.
#[cfg(debug_assertions)]
fn test_server_of(value: &str) -> Option<String> {
    let value = value.trim().trim_end_matches('/');
    (value.starts_with("http://127.0.0.1:") || value.starts_with("http://localhost:"))
        .then(|| value.to_string())
}

/// The override, when this is a debug build and it is set: `Some(None)` is
/// "no server".
#[cfg(debug_assertions)]
pub(crate) fn test_server() -> Option<Option<String>> {
    std::env::var(TEST_SERVER_ENV)
        .ok()
        .map(|value| test_server_of(&value))
}

#[cfg(not(debug_assertions))]
pub(crate) fn test_server() -> Option<Option<String>> {
    None
}

/// Natively no redirect is followed: the body goes to the server named here
/// and nowhere it points to. The browser follows redirects itself.
pub(crate) fn http_client() -> anyhow::Result<reqwest::Client> {
    let builder = reqwest::Client::builder();
    #[cfg(not(target_arch = "wasm32"))]
    let builder = builder.redirect(reqwest::redirect::Policy::none());
    builder
        .build()
        .map_err(|e| anyhow::anyhow!("HTTP client build failed: {e}"))
}

#[cfg(all(test, not(target_arch = "wasm32")))]
pub(crate) mod tests {
    pub(crate) use super::wake::tests::{serve, woken, Seen};

    #[cfg(debug_assertions)]
    use super::test_server_of;

    #[cfg(debug_assertions)]
    #[test]
    fn the_test_override_names_a_loopback_server_or_none() {
        for (value, server) in [
            ("http://127.0.0.1:7002", Some("http://127.0.0.1:7002")),
            ("http://localhost:7002/", Some("http://localhost:7002")),
            ("off", None),
            ("", None),
            ("https://mostro-push-server.fly.dev", None),
            ("http://127.0.0.1.example.com:80", None),
            ("http://localhost.example.com", None),
        ] {
            assert_eq!(test_server_of(value).as_deref(), server, "{value:?}");
        }
    }
}
