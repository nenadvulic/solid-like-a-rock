# Security rules reference

One section per rule. Every rule is matched on the real syntax tree
(SwiftSyntax), never with regex over source text — a commented-out
`SecTrustEvaluate` can neither trigger nor suppress a finding, because
comments are trivia, not tokens.

Severity resolves in three steps: per-rule `rules.<id>.severity` >
global `security.severity` > the built-in default shown in each heading.

Suppress a single finding with `// solid:ignore <reason>` on the flagged line
or the line above — the reason is mandatory. Turn a rule off entirely with
`disable: [ruleID]`. Details in [Suppressing and tuning](#suppressing-and-tuning).

A recurring theme below: each rule's **Not flagged** list is not a gap, it is
the calibration. These rules were tuned against real codebases (Signal-iOS,
isowords) until the false positives died; when a rule stays silent it is
because the pattern is *provably* harmless or there is no proof of a problem.
No proof, no noise.

---

## Keychain

### keychainAccessibleAlways (error)

**Detects** any reference to `kSecAttrAccessibleAlways` or
`kSecAttrAccessibleAlwaysThisDeviceOnly` — plain identifier match, anywhere
in the file.

**Why it matters** These protection classes keep the Keychain item decryptable
*while the device is locked*. A stolen, locked phone — or any forensic tooling
that talks to a locked device — can read the item. Apple deprecated both
constants for exactly this reason.

**Example**

```swift
// Bad — readable while locked
let query: [String: Any] = [
    kSecAttrAccessible as String: kSecAttrAccessibleAlways,
]

// Good — protected by the device lock, never migrates to another device
let query: [String: Any] = [
    kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
]
```

**Not flagged** Every other accessibility constant
(`kSecAttrAccessibleWhenUnlocked`, `…AfterFirstUnlock`, …). The rule reports
the exact identifier it found, so `…AlwaysThisDeviceOnly` is never misreported
as its prefix.

### keychainMissingAccessibility (error)

**Detects** a `SecItemAdd` call whose query dictionary *literal* — written
inline, or assigned to a `let` that is visible in the same file — contains
`kSecClass` but no `kSecAttrAccessible`.

**Why it matters** Without an explicit accessibility attribute the item
silently gets the OS default protection class. Maybe that default is fine for
your item, maybe not — but nobody *decided*, and a reviewer reading the query
cannot tell what protection the item actually has. Security-sensitive defaults
should be visible in the code.

**Example**

```swift
// Bad — protection class left to the OS default
let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecValueData as String: data,
]
SecItemAdd(query as CFDictionary, nil)

// Good — the decision is explicit
let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecValueData as String: data,
    kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
]
SecItemAdd(query as CFDictionary, nil)
```

**Not flagged** — every exemption here is about *proof of the final dictionary
contents*:

- Dictionaries built dynamically or out of file
  (`SecItemAdd(makeQuery() as CFDictionary, nil)`) — no literal, no proof.
- `var` dictionaries — they can gain `kSecAttrAccessible` after the fact via
  `query[...] = ...`, so the literal is not the final contents.
- Names bound to *more than one* literal in the file. Keychain wrappers
  canonically declare `let query` in each method (save/find/delete); resolving
  `SecItemAdd`'s `query` to another method's literal would be wrong, so
  ambiguous names stay silent.
- Queries carrying `kSecAttrAccessControl`. It is mutually exclusive with
  `kSecAttrAccessible` (the `SecAccessControl` object carries its own
  protection class) — adding the "missing" key would actually break the call.
  This is the *most* secure pattern; it satisfies the rule.

### sensitiveDataInUserDefaults (warning)

**Detects** `defaults.set(_, forKey: "literal")` / `setValue(_, forKey:)` on a
UserDefaults-looking base (any base whose text contains `defaults` — covers
`UserDefaults.standard` and custom wrappers alike) where the *literal* key
matches a PII word: `firstName`, `lastName`, `email`, `phone`, `ssn`, `dob`,
`homeAddress`, `userId`, … Whole-word matching across camelCase and
snake_case, so `user_email` and `userEmail` both fire.

**Why it matters** UserDefaults is a cleartext plist on disk. It ships in
device backups and is trivially readable from an unencrypted backup or any
jailbroken device. Unlike a credential, storing a display name *can* be
deliberate — hence warning, not error.

**Example**

```swift
// Bad — PII in a cleartext plist
UserDefaults.standard.set(user.email, forKey: "userEmail")

// Good — Keychain (or encrypted storage) for personal data
keychain.set(user.email, for: .userEmail)
```

**Not flagged**

- Keys owned by `tokenInUserDefaults` — `authToken`, `userToken` and friends
  are excluded at *key* level, so one store produces exactly one finding (the
  credential one, at error severity), never two.
- `Bool`/`Int` literal values: `defaults.set(true, forKey: ...)` is provably a
  preference flag, not PII, whatever the key says.
- Non-literal keys (`forKey: dynamicKey`) — no proof of what is stored.
- Bare `name`/`user`/`address` words are deliberately absent from the list:
  `displayName`, `userInterfaceStyle`, `serverAddress`, `fontName` are UI and
  infrastructure keys, not PII. Only qualified pairs (`firstName`,
  `homeAddress`, `phoneNumber`) are provably personal.

---

## Crypto

### insecureHash (error)

**Detects** CryptoKit's `Insecure.MD5` / `Insecure.SHA1` (bare or
module-qualified as `CryptoKit.Insecure.MD5`) and CommonCrypto's `CC_MD5` /
`CC_SHA1`.

**Why it matters** MD5 and SHA-1 are not collision-resistant — attackers can
craft two inputs with the same digest on commodity hardware. Anything
security-relevant built on them (signatures, integrity checks, password
hashing) is broken.

**Example**

```swift
// Bad
let digest = Insecure.MD5.hash(data: payload)

// Good
let digest = SHA256.hash(data: payload)
```

**Not flagged** `SHA256` and stronger. There is no "looks like hashing"
heuristic — only the four broken symbols fire. Legitimate non-security uses
(ETag computation, cache keys, dedup against a legacy system) are exactly what
`// solid:ignore <reason>` is for:

```swift
let etag = Insecure.MD5.hash(data: body) // solid:ignore server requires MD5 ETags
```

### hardcodedSecret (error)

**Detects** a string literal assigned to a secret-named identifier — `apiKey`,
`password`, `token`, `secret`, `credential`, `passphrase`, `jwt`, `key` —
matched whole-word across camelCase/snake_case (`awsSecretKey`, `db_password`
fire; `monkey` does not). Pure name heuristic: entropy analysis lives in
`highEntropySecret`.

**Why it matters** A secret compiled into the binary is not a secret. Strings
are extracted from any .ipa in seconds (`strings`, Hopper), and the value lives
forever in git history even after you "remove" it.

**Example**

```swift
// Bad — shipped to every device, forever in git history
let apiKey = "sk-live-abcdef123456"

// Good — injected at build/run time, or stored in the Keychain
let apiKey = ProcessInfo.processInfo.environment["API_KEY"] ?? loadFromKeychain()
```

**Not flagged** — the value filters are the heart of this rule. A secret-named
variable stays silent when its *value* is identifier-shaped rather than
secret-shaped:

- Placeholders and templates: `"changeme"`, `"YOUR_API_KEY"`, `"${API_KEY}"`,
  `"<insert>"`, anything under 8 characters.
- Interpolated strings (`"prefix-\(dynamic)"`) — not a hardcoded constant.
- URLs (`"https://auth.example.com/token"`) — endpoints are not secrets.
- Header names (`"X-Api-Key"`) — labels, not secrets.
- Reverse-DNS / keypath shapes (`"com.app.lastSyncDate"`,
  `"user.profile.image"`) — UserDefaults keys, the most common iOS string
  idiom. Segments are capped at 20 characters, so JWTs (long base64url
  segments joined by dots) still fire.
- Single pure-alpha words (`"tokenRefreshedNotification"`) — overwhelmingly
  identifiers. Accepted trade-off: an alpha-only password with no digits or
  symbols slips through; real secrets carry digit/symbol entropy.
- Identifier-shaped phrases: words separated by `_ - /` or space, each word
  letters plus at most 3 trailing digits. This clears Signal-style storage-key
  names (`"kNSUserDefaults_FirstAppVersion"`, `"x-signal-checksum-sha256"`,
  `"v2/keys/signed"`, `"Screen Security Key"`) while keeping real keys flagged
  — `"sk-live-abcdef123456"` has a long digit run, `"wJalrXUtnFEMI/K7MDENG/…"`
  has interior digits; neither is word-shaped.
- A value that echoes its own identifier
  (`let kOWS2FAManager_…Key = "kOWS2FAManager_…Key"`) is a key *name* by
  construction, never a secret value.

### highEntropySecret (warning)

**Detects** a long, high-entropy base64 or hex string literal *anywhere* in
the code, whatever the variable is called. Two gates, because the alphabets
cap entropy differently: base64-charset literals need length ≥ 20 and Shannon
entropy > 4.5 bits/char; hex-charset literals (a 16-symbol alphabet maxes out
at 4.0 bits/char) need length ≥ 32 — a 128-bit key — and entropy > 3.5.

**Why it matters** An embedded key with a bland name (`let blob = ...`) walks
straight past name-based detection. Entropy doesn't care what you called it.

**Example**

```swift
// Bad — 48 chars of base64, entropy ~4.6 bits/char: that is key material
let blob = "dGhpc2lzYXZlcnlsb25nc2VjcmV0a2V5MTIzNDU2Nzg5MA=="

// Good — fetched/derived at runtime, never a literal
let blob = try keyProvider.sessionKey()
```

**Not flagged**

- Alphabet/charset tables: a literal in which *every character is distinct*
  (like the base64 alphabet itself) is high-entropy by construction but never
  a secret — real keys drawn from a ≤ 64-symbol alphabet repeat characters at
  these lengths. (This gate exists because the rule once flagged the base64
  alphabet inside its own source.)
- Low-entropy strings: `"aaaaaaaa…"` (entropy 0), `"deadbeefdeadbeef…"`
  (English-y hex words sit around 2 bits/char, far under the 3.5 gate).
- Anything outside the base64/hex charsets — an English sentence contains
  spaces and punctuation and never reaches the entropy check.
- Short strings (under the per-charset length gates).

Warning by default: test fixtures trip it legitimately — suppress those with
`// solid:ignore test fixture`.

---

## Network

### cleartextHTTP (error)

**Detects** `Info.plist` files (exactly that name, found under the lint roots)
where `NSAppTransportSecurity.NSAllowsArbitraryLoads` is `true`. This is the
one check that reads plists instead of Swift syntax trees.

**Why it matters** `NSAllowsArbitraryLoads = true` turns App Transport
Security off for *every* connection the app makes. Any request can silently
downgrade to cleartext HTTP, and anyone on the same network — coffee-shop
Wi-Fi, a hostile hotspot — reads and modifies the traffic.

**Example**

```xml
<!-- Bad — ATS off globally -->
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>

<!-- Good — scope the exception to the one legacy domain that needs it -->
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSExceptionDomains</key>
    <dict>
        <key>legacy.example.com</key>
        <dict>
            <key>NSExceptionAllowsInsecureHTTPLoads</key>
            <true/>
        </dict>
    </dict>
</dict>
```

**Not flagged** Per-domain exceptions (`NSExceptionDomains`) — that is the
fix, not the problem. Plists under `exclude:` paths, and corrupt or unreadable
plists, are skipped the same way unreadable Swift files are.

### disabledTLSValidation (error)

**Detects** a `urlSession(_:didReceive:completionHandler:)` auth-challenge
handler that passes `.useCredential` a `URLCredential(trust:)` built from the
server trust *without* any `SecTrustEvaluate*` call
(`SecTrustEvaluateWithError`, `SecTrustEvaluateAsync`, … all count). Matching
is done on the body's *tokens*, so a commented-out `// TODO: call
SecTrustEvaluate` neither suppresses nor triggers anything.

**Why it matters** Accepting the server trust without evaluating it trusts
*any* certificate. Every MITM proxy with a self-signed cert — Charles on a
test device, a corporate middlebox, an attacker on public Wi-Fi — reads and
rewrites every byte of "TLS" traffic. This pattern is usually a dev-time hack
that ships.

**Example**

```swift
// Bad — trust-all: any certificate is accepted
func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
    completionHandler(.useCredential, URLCredential(trust: challenge.protectionSpace.serverTrust!))
}

// Good — evaluate, and be able to reject
func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
    let trust = challenge.protectionSpace.serverTrust!
    guard SecTrustEvaluateWithError(trust, nil) else {
        return completionHandler(.cancelAuthenticationChallenge, nil)
    }
    completionHandler(.useCredential, URLCredential(trust: trust))
}
```

**Not flagged**

- Handlers containing any `SecTrustEvaluate*` token — system trust evaluation
  happens.
- Handlers with a `.cancelAuthenticationChallenge` branch: if the code *can*
  reject the challenge, validation logic exists somewhere — this is what keeps
  TrustKit-style wrapper pinning (`guard pinner.validate(trust) else { ... }`)
  silent. Deliberate trade-off: a trust-all with a decorative cancel path
  would be missed, but provability wins over sensitivity.
- Functions that merely look similar — the rule requires the `urlSession` name
  *and* a `didReceive` parameter.

### httpURLLiteral (warning)

**Detects** any string literal starting with `http://`, minus a calibrated
set of hosts that are never real network endpoints. Complements the
`cleartextHTTP` plist check: ATS exceptions are useless without someone
actually writing `http://` URLs.

**Why it matters** A cleartext URL is readable and modifiable by every hop on
the path — and ATS will block the request in production anyway, so it is
either a latent bug or evidence of an ATS exception that shouldn't exist.

**Example**

```swift
// Bad
let url = URL(string: "http://api.example.com/v1")

// Good
let url = URL(string: "https://api.example.com/v1")
```

**Not flagged** — these are identifier shapes or dev plumbing, not endpoints:

- Loopback and dev hosts: `localhost`, `127.0.0.1`, IPv6 loopback in both
  forms (`http://::1/health`, `http://[::1]:8080/x`), and `*.local` mDNS
  hosts. Ports are stripped before matching.
- XML namespace / DTD authority hosts (`www.w3.org`, `schemas.android.com`,
  `purl.org`, `ns.adobe.com`, `www.apple.com`, …): these strings are opaque
  identifiers compared byte-for-byte, never fetched.
- Any path ending in `.dtd` — a DTD system identifier, not a live endpoint.
- The bare `"http://"` prefix literal, as used in `url.hasPrefix("http://")`.

Warning by default — dev tooling and tests legitimately reference http
endpoints.

---

## Auth

### tokenInUserDefaults (error)

**Detects** `defaults.set(_, forKey: "literal")` / `setValue(_, forKey:)` on a
UserDefaults-looking base where the literal key matches a credential word:
`token`, `jwt`, `password`, `secret`, `credential` — whole-word, so
`authToken`, `user_password`, `refreshToken` and plain `JWT` all fire.

**Why it matters** A credential in UserDefaults sits in cleartext on disk and
in every device backup. There is no legitimate variant of this — credentials
belong in the Keychain, full stop. That is why this one is an error while its
PII sibling is a warning.

**Example**

```swift
// Bad — cleartext on disk, in backups
UserDefaults.standard.set(jwt, forKey: "authToken")

// Good
keychain.set(jwt, for: .authToken)
```

**Not flagged**

- Bare `auth` is deliberately *not* in the word list: it overwhelmingly names
  preference flags (`biometricAuthEnabled`, `requireAuthOnLaunch`), not
  credentials. Real credentials still match via their own words —
  `authToken` fires on `token`.
- `Bool`/`Int` literal values — `defaults.set(true, forKey:
  "biometricAuthEnabled")` is provably a flag, whatever the key says.
- Non-literal keys (`forKey: dynamicKey`) — no proof.

Custom wrappers are covered: any base containing `defaults`
(`appDefaults.set(...)`) matches, not just `UserDefaults.standard`.

### biometryNoErrorHandling (error)

**Detects** `canEvaluatePolicy(_, error: nil)` where the *result is used* —
in an `if`, a `guard`, or bound to a variable.

**Why it matters** The `error` out-parameter is the only signal explaining
*why* biometrics are unavailable: lockout after failed attempts, nothing
enrolled, passcode not set. Passing `nil` and branching on the Bool collapses
all of those into "no", and the user gets a dead button instead of "Face ID is
locked — enter your passcode".

**Example**

```swift
// Bad — every failure reason becomes a silent false
if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) { ... }

// Good — lockout and not-enrolled get their own handling
var error: NSError?
if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
    ...
} else if let error { handleBiometryError(error) }
```

**Not flagged** A *bare statement* call that discards the result too:

```swift
context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
let type = context.biometryType
```

This is Apple's documented idiom — `canEvaluatePolicy` must be called before
reading `biometryType`. No auth decision is made, so there is no ignored
failure path. (Calibrated against Signal-iOS, which uses exactly this.)
Binding the result (`let ok = ...`) with `error: nil` stays flagged.

### biometryNoFallback (warning)

**Detects** any use of `.deviceOwnerAuthenticationWithBiometrics` outside a
`case` pattern.

**Why it matters** The biometrics-only policy has no passcode fallback: after
a few failed Face ID attempts the user is locked out of the feature entirely.
`.deviceOwnerAuthentication` falls back to the device passcode automatically.

**Example**

```swift
// Bad — failed Face ID is a dead end
context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: r) { ok, err in }

// Good — the system offers the passcode after biometric failure
context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: r) { ok, err in }
```

**Not flagged** `case .deviceOwnerAuthenticationWithBiometrics:` in a switch —
a case pattern is provably *handling* a policy someone else selected, not
selecting one. Plain `== .deviceOwnerAuthenticationWithBiometrics` comparisons
are not provably harmless and stay flagged. Warning by default: apps that
implement their own fallback UI suppress the call site with
`// solid:ignore custom PIN fallback`.

---

## Logging

### publicPIIInLog (error)

**Detects** an os_log/Logger string interpolation that combines a PII-named
value with `privacy: .public` — e.g. `\(email, privacy: .public)`. For member
accesses, the *last* component is what is evaluated: `session.authToken`
fires on `authToken`.

**Why it matters** os_log redacts dynamic values by default — `privacy:
.public` is an explicit opt-out. A public PII interpolation puts the value in
the unified log, readable in Console.app and shipped inside every sysdiagnose
the user sends to anyone.

**Example**

```swift
// Bad — redaction explicitly defeated for PII
logger.info("user: \(email, privacy: .public)")

// Good — redacted in the log; or use a non-identifying hash
logger.info("user: \(email, privacy: .private)")
```

**Not flagged** `privacy: .private` and interpolations with no privacy
argument (the default is private — already redacted). Non-PII names
(`\(requestCount, privacy: .public)`) — publishing a counter is the entire
point of the API.

### printSensitiveData (warning)

**Detects** `print` / `debugPrint` / `NSLog` / `dump` calls where what is
*actually printed* has a sensitive name. "Actually printed" means: a bare
identifier (`print(password)`), the last component of a member access
(`print(viewModel.username)`), or those same shapes inside string
interpolation (`print("logging in \(userEmail)")`). Matched against the
combined PII + secret word lists.

**Why it matters** Unlike os_log, `print` and `NSLog` have no privacy
redaction, ship in release builds, and end up in sysdiagnoses and crash-report
attachments. A token printed once is a token leaked.

**Example**

```swift
// Bad — the token lands in the console and in sysdiagnoses
print("u: \(session.authToken)")

// Good — os_log redacts by default
logger.debug("user session refreshed")
```

**Not flagged** — the calibration here is what makes the rule usable:

- Bases of member accesses: `tokens.count` prints a count, `token.kind`
  prints a kind — only the last component is evaluated, so neither fires
  while `session.authToken` still does.
- Bare `key` is excluded from the word list: `keyWindow`, `keyPath` and
  `for (key, value) in dict` loops are ubiquitous Swift idioms carrying no
  secret. Multiword forms (`apiKey`, `storeKey`) still fire.
- Static string content never triggers — only interpolated expressions are
  inspected, so `print("press any key")` is silent.
- Function-call results and array literals as arguments are ignored — no
  identifier to judge.

---

## Suppressing and tuning

### solid:ignore

```swift
let etag = Insecure.MD5.hash(data: body) // solid:ignore server requires MD5 ETags
```

- Works on the flagged line or the line above; the *reason is mandatory* — a
  bare `// solid:ignore` suppresses nothing.
- The directive must *start* the comment body; a mid-comment mention does not
  count.
- Granularity is the enclosing **statement**: a directive above (or at the end
  of) a multi-line statement suppresses findings anywhere inside that
  statement. There is no file-level or block-level ignore — that is
  deliberate; broad waivers belong in config, with review.

### disable and severity

```yaml
security:
  enabled: true
  severity: warning          # optional: override every rule's default
  disable: [highEntropySecret]
  rules:
    printSensitiveData:
      severity: error        # per-rule override beats the global one
```

Precedence: `rules.<id>.severity` > `security.severity` > the rule's built-in
default (shown in each heading above). Unknown rule IDs anywhere in the config
are rejected before linting — a typo cannot silently disable nothing.

### Baseline — adopting on a legacy codebase

Don't fix 200 findings on day one. Snapshot them, then fail only on new ones:

```bash
solid-like-a-rock --write-baseline .solid-baseline.json Sources   # once, commit the file
solid-like-a-rock --baseline .solid-baseline.json Sources          # CI: new findings only
```

A finding's identity excludes the line number, so editing code above a
baselined finding does not resurface it as "new". The baseline file is plain,
sorted JSON — diff-friendly and safe to commit.
