# 🍽️ Restaurant Hygiene Monitoring & Complaint Management System

> A mobile-first system that lets the public report restaurant hygiene issues, gives authorities a structured pipeline to verify and act on complaints, and uses hygiene data to guide diners toward safer restaurants.

## 📖 Overview

Restaurant hygiene issues are often reported inconsistently and hard to track from complaint to resolution. This system gives the public a simple way to report hygiene issues with photo/GPS evidence, gives admins a verification pipeline, routes verified cases to government inspectors for enforcement, and surfaces the resulting hygiene data back to users as safety recommendations and a risk heatmap.

## Features and roles

| Role | Main features |
| --- | --- |
| Customer | Register/sign in; search restaurants; view maps, recommendations, risk details and rankings; submit photo-supported complaints; track reports, reviews and bookmarks. |
| Businessman / owner | Submit restaurant details, location, photos and SSM evidence; monitor notices; upload rectification evidence; settle fines; view compliance and resolution reports. |
| Admin | Approve restaurant applications; verify complaint evidence; review inspection reports; manage accounts, dashboard analytics and action logs. |
| Government / officer | Review verified complaints; schedule and record inspections; issue enforcement after report approval; review compliance and close eligible cases. |

Shared features include notifications, next-action dashboard links, activity history, profile settings and local caching. This is an academic application, not an official government service or independent hygiene certification.

## Architecture and source layout

The project separates Flutter presentation, Dart application/business services, and Supabase data/backend services. Some decisions and calculations remain in screens. SharedPreferences stores device caches/settings; database functions handle critical inspection/payment transitions.

| Path | Responsibility |
| --- | --- |
| `lib/main.dart` | Startup and route wiring |
| `lib/auth/` | Login, registration, accounts and settings |
| `lib/gps/` | Restaurant discovery, maps and outlet applications |
| `lib/report/` | Customer complaint submission and tracking |
| `lib/complaint/` | Administrative verification and report review |
| `lib/inspect/` | Government inspection/enforcement |
| `lib/owner/` | Owner dashboard, compliance and payments |
| `lib/risk/` | Recommendations, risk details and rankings |
| `lib/notifications/` | Notification centre |
| `lib/core/` | Models, services, configuration, routes, widgets, themes and utilities |
| `assets/` | Branding, images and videos |
| `android/`, `ios/` | Native platform configuration |

Read `lib/core/services/data_sync_service.dart`, `restaurant_store_service.dart`, `customer_store_service.dart` and `workflow_service.dart` to trace data and workflows. Environment readers are in `lib/core/config/app_env.dart`.

Dependencies include Supabase, Google Maps, location/voice input, Firebase messaging, Stripe, email delivery, image picking, OCR and PDF generation. Versions are declared in `pubspec.yaml` and resolved in `pubspec.lock`.

## Install the released APK on an Android phone

**For tutors who want to evaluate the application:** install the ready-built APK from GitHub Releases. Flutter, Android Studio, a computer, wireless debugging and a local `.env` file are not required for this method. To build or inspect the source instead, follow [Install and run](#install-and-run).

### 1. Download the APK

1. On the Android phone, open Chrome or another browser.
2. Open [HygieneTruth Releases](https://github.com/LowYoongQian/HygieneTruth/releases), or go to the repository and select **Releases**.
3. Open the release labelled **Latest**. At the time of checking on **21 September 2026**, this was [v0.3.0](https://github.com/LowYoongQian/HygieneTruth/releases/tag/v0.3.0).
4. Scroll to **Assets** and expand it if necessary.
5. Tap **HygieneTruth.apk** and wait for the download to finish (approximately **167 MB** for v0.3.0). Select the APK, not **Source code (zip)** or **Source code (tar.gz)**, which contain source files rather than the installable app.

Direct download of the checked version: [HygieneTruth.apk — v0.3.0](https://github.com/LowYoongQian/HygieneTruth/releases/download/v0.3.0/HygieneTruth.apk). Use the Releases page above to check for newer versions; this direct link stays on v0.3.0.

### 2. Install and open

1. Tap the completed download, or open the phone's **Files / My Files > Downloads** and select `HygieneTruth.apk`.
2. If Android asks for installation permission, open **Settings** from that prompt. Allow the specific app opening the APK (for example, Chrome or My Files) to **Install unknown apps / Allow from this source**, then return to the APK.
3. Tap **Install**, wait for completion, then tap **Open**. Later, launch HygieneTruth from the phone's app list.
4. After installation, you can turn off that source's installation permission again. Menu labels vary by manufacturer; see [Samsung's installation-permission guide](https://www.samsung.com/ae/support/mobile-devices/how-to-enable-permission-to-install-apps-from-unknown-source-on-my-samsung-phone/).

### 3. Sign in and evaluate the system

1. Keep internet access enabled: shared accounts, records, images, maps and payments depend on hosted services. The installed APK uses configuration packaged by the maintainer; the tutor does not create or edit `.env` on the phone.
2. Complete the opening/onboarding screens if shown, then open the login screen.
3. Use **Switch Login Portal** to select the relevant portal:

   | Account to evaluate | Login route |
   | --- | --- |
   | Customer | **Customer**; register a customer account or use the supplied assessment account. |
   | Restaurant owner | **Businessman (Business)**; register a business account or use the supplied assessment account. |
   | Admin | **Official Staff (Admin / Gov)**, then select Admin and use the supplied administrator credentials. |
   | Government officer | **Official Staff (Admin / Gov)**, then select Government and use the supplied officer credentials. |

4. Obtain privileged assessment credentials privately from the project maintainer. Selecting a portal does not create an account or grant its role.
5. When using the corresponding features, allow location access for nearby results/maps, microphone access for voice input and notifications for alerts; select photos when evidence is requested.
6. Follow [Using the application](#using-the-application) for the owner → admin → customer → government demonstration. Sign out before switching accounts, or use separate devices for the roles. Use assessment data and maintainer-confirmed Stripe test mode for payment demonstrations.

### 4. Update or troubleshoot the APK

To update, revisit Releases, download the newer APK and open it to install the update. A compatible update normally retains local app data; its signing identity must match the installed build.

| Problem | What the tutor should do |
| --- | --- |
| Downloaded a ZIP | Return to the release's **Assets** and select `HygieneTruth.apk`. |
| Download incomplete or APK cannot be parsed | Check free storage, download the file again and report the Android version/error to the maintainer if it persists. |
| Installation permission denied | Check permission for the browser/file manager actually opening the APK; managed phones may require the device administrator's permission. |
| App not installed / package conflicts with an existing app | Send the error to the maintainer to check compatibility and signing. Do not uninstall by default: uninstalling removes local app data. |
| APK opens but login, images or data fail | Check internet and assessment credentials, then contact the maintainer about the hosted configuration. Editing `.env` on the phone cannot repair an already-built APK. |

The release asset's availability was verified; installation on the tutor's particular phone has not been tested.

## Requirements

The following requirements apply to building/running from source; APK-only users can use the installation guide above.

- Git and Flutter on PATH. The inspected environment uses **Flutter 3.41.4 / Dart 3.11.1**; the project requires Dart `^3.11.1`.
- Android Studio/SDK, compatible **JDK 17**, and an Android device or emulator. Compile SDK is **36**, target SDK **34**, and Java/Kotlin target **17**.
- Internet and authorised access to a configured Supabase backend.
- Maps/Firebase configuration, plus Google login, email and Stripe test credentials when demonstrating those integrations.

Android is the documented target. iOS/web/desktop support has not been validated by this review. See the [Flutter installation guide](https://docs.flutter.dev/install).

## Install and run

Follow these steps in order on the tutor's Windows computer. Commands run in PowerShell or Android Studio's Terminal. Menu wording may vary slightly by Android Studio/phone version.

### 1. Prepare Flutter and Android Studio

1. Install Git and the Flutter SDK. Add Flutter's `bin` folder to your Windows user `Path`, then reopen terminals. Check `git --version` and `flutter --version`. Installing the IDE plugin alone does not install Flutter.
2. Install/open Android Studio. Open **More Actions > SDK Manager** on the welcome screen, or **Tools > SDK Manager** inside a project.
3. Under **SDK Platforms**, install **Android API 36**, matching this project's compile SDK. Under **SDK Tools**, install/update **Android SDK Platform-Tools**, **Android SDK Command-line Tools (latest)** and **Android SDK Build-Tools**. Allow any project-requested NDK components to install. Install **Android Emulator** if using a virtual device.
4. Run `flutter doctor --android-licenses`, review/accept the required licences, then run `flutter doctor -v`. Resolve Android toolchain errors before continuing; a missing Windows desktop toolchain is not required for this Android run.

Reference: [Flutter Android environment setup](https://docs.flutter.dev/platform-integration/android/setup).

In Android Studio, open **File > Settings > Plugins > Marketplace**, install **Flutter**, accept its Dart plugin dependency and restart. Under **Settings > Languages & Frameworks > Flutter**, select the installed Flutter SDK directory if it is not detected. Reference: [Flutter in Android Studio](https://docs.flutter.dev/tools/android-studio).

### 2. Open and configure this project

1. Clone the repository:

   ```powershell
   git clone https://github.com/LowYoongQian/HygieneTruth.git
   cd HygieneTruth
   ```

2. In Android Studio select **Open**, then the **HygieneTruth root folder containing `pubspec.yaml`**, rather than only its `android` subfolder. For a supplied ZIP, extract it first and open that same project root.
3. Create **`.env`** beside `pubspec.yaml` using [Environment configuration](#environment-configuration). Enable Windows Explorer's file-name extensions and ensure the file is not `.env.txt`.
4. Obtain authorised client configuration and demonstration accounts privately from the project maintainer. Complete [Backend and integration setup](#backend-and-integration-setup), including the matching Firebase file and Maps configuration. **An empty Supabase project is insufficient.**
5. Open **View > Tool Windows > Terminal**. Confirm `Get-Location` points to the project root and `Test-Path pubspec.yaml` returns `True`, then run:

   ```powershell
   flutter clean
   flutter pub get
   ```

`flutter clean` removes generated build output and `.dart_tool`; `flutter pub get` restores the packages/configuration needed for the next build. This clean sequence is useful for a fresh assessment copy or stale build problems; it is not needed before every run and does not erase Supabase data. Keep `pubspec.lock` to retain the project's resolved dependency versions. Reference: [Flutter command-line reference](https://docs.flutter.dev/reference/flutter-cli).

### 3. Connect an Android phone wirelessly

The pairing workflow below requires **Android 11 or newer**, current Platform-Tools and the computer/phone on the **same Wi-Fi network**. No initial USB connection is required for this method.

1. On the phone, open **Settings > About phone > Build number** and tap it seven times; enter the phone PIN if requested. On Samsung, Build number is usually under **About phone > Software information**.
2. Return to Settings and open **Developer options** (sometimes under System), then enable **Wireless debugging** and approve the current network.

Reference: [Android Developer options](https://developer.android.com/studio/debug/dev-options).

3. In Android Studio, open the device selector and choose **Pair Devices Using Wi-Fi**; this option is also available through Device Manager in supported versions.
4. Choose **Pair using pairing code**. On the phone's Wireless debugging page, select **Pair device with pairing code**. Keep that page open.
5. In Android Studio select the detected phone, enter the displayed six-digit code and choose **Pair**. Alternatively select QR pairing and scan Studio's QR code through the phone's **Pair device with QR code** option.
6. Wait until the phone appears connected in Android Studio, then return to the project terminal and run `flutter devices`. Confirm an **Android** device is listed, rather than only Chrome or Windows.

Reference: [Android Studio wireless device pairing](https://developer.android.com/studio/run/device#connect-to-your-device-using-wi-fi).

### 4. If pairing succeeds but Flutter cannot see the phone

Use Android SDK Platform-Tools' `adb` to check the connection. If it is not on PATH, find **Android SDK Location** in SDK Manager; use that directory in place of the example below:

```powershell
$androidAdb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
& $androidAdb devices -l
```

If Studio cannot pair, manually pair using the address/port on the phone's **pairing-code popup**:

```powershell
& $androidAdb pair PHONE_IP:PAIRING_PORT
```

Enter the code when prompted. If paired but disconnected, use **IP address & Port from the main Wireless debugging page**:

```powershell
& $androidAdb connect PHONE_IP:CONNECTION_PORT
& $androidAdb devices -l
flutter devices
```

Replace the uppercase placeholders with phone values; the pairing and connection ports are different and can change. ADB should show status `device`. See the [ADB connection guide](https://developer.android.com/tools/adb).

| Connection problem | Action |
| --- | --- |
| Phone not detected on university/guest Wi-Fi | The network may isolate devices. Use a permitted network allowing local connections, or USB. Check VPN/firewall restrictions without disabling protection globally. |
| `offline` or disconnected | Unlock the phone, check Wireless debugging, reconnect using its current address/port and rerun `flutter devices`. |
| Pairing code rejected | Reopen the pairing-code popup and use its new code and pairing port. |
| `adb` is not recognised | Use the full Platform-Tools path above, matching SDK Manager's actual location. |
| `flutter` is not recognised | Add the Flutter SDK's `bin` directory to PATH and reopen the terminal. |

### 5. Run HygieneTruth on the phone

In the project-root terminal:

```powershell
flutter devices
flutter run -d "DEVICE_ID_FROM_FLUTTER_DEVICES"
```

Replace the quoted placeholder with the **exact device ID** reported by Flutter, including a wireless service-style ID if shown. With only one suitable device, `flutter run` also works. The first build may take several minutes while dependencies download; wait for installation and the Flutter debug connection.

Alternatively, open `lib/main.dart` in Android Studio, select the paired phone and the Flutter `main.dart` run configuration, then click **Run**. Use either the terminal or IDE for the active run, rather than starting both simultaneously.

When the app opens, allow relevant permissions and follow [Using the application](#using-the-application). Successful installation should lead to the app's opening/login flow; successful setup also requires checking sign-in, restaurant loading, images and Maps against the configured backend.

In the active terminal, `r` hot reloads, `R` hot restarts and `q` ends the run. Stop and rerun after changing `.env`; rebuild after native configuration changes. For ordinary subsequent runs, reconnect the phone and run `flutter run`; repeat `flutter pub get` when dependencies change. The controls and device targeting are documented in the [Flutter CLI guide](https://docs.flutter.dev/reference/flutter-cli).

### 6. USB or emulator fallback

- **USB:** enable USB debugging in Developer options, connect a data-capable cable, unlock the phone and accept the computer authorisation prompt. On Windows, install the manufacturer's ADB driver if needed. Run `flutter devices` and use the same run command. This is also an alternative for phones below Android 11. See [Android USB setup](https://developer.android.com/studio/run/device#connect-to-your-device-using-usb).
- **Emulator:** open Device Manager, create a phone with an API 36 Google Play system image, download it and start the device; select its ID from `flutter devices`. Location must be supplied through emulator controls for meaningful nearby results.

To produce an assessment APK, run `flutter build apk --debug`. Output: `build/app/outputs/flutter-apk/app-debug.apk`. The current release configuration also uses debug signing; proper release signing is required before distribution.

## Environment configuration

The Git-ignored `.env` is **bundled as a Flutter asset**, so it is not a safe place for server secrets. Never include Supabase service-role credentials or production server keys. Replace these placeholders privately:

```dotenv
APP_ENV=development
APP_NAME=HygieneTruth
APP_VERSION=0.1.0
SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co
SUPABASE_ANON_KEY=YOUR_PROJECT_ANON_KEY
GOOGLE_MAPS_API_KEY=YOUR_ANDROID_MAPS_KEY
GOOGLE_WEB_CLIENT_ID=YOUR_WEB_OAUTH_CLIENT_ID
DEFAULT_LATITUDE=3.1466
DEFAULT_LONGITUDE=101.6958
STORAGE_BUCKET_NAME=Images
STRIPE_PUBLISHABLE_KEY=YOUR_STRIPE_TEST_PUBLISHABLE_KEY
```

Use an unquoted Maps key: Android Gradle reads it directly into the manifest. Client keys still require provider restrictions and database policies.

| Variable | Purpose / caveat |
| --- | --- |
| `SUPABASE_URL`, `SUPABASE_ANON_KEY` | Backend URL and client anon key, never the service-role key. |
| `GOOGLE_MAPS_API_KEY` | Android maps and routing; enable matching APIs and restrictions. |
| `GOOGLE_WEB_CLIENT_ID` | Web OAuth client ID used by Google login, not the Android client ID. |
| `DEFAULT_LATITUDE`, `DEFAULT_LONGITUDE` | Fallback location in Kuala Lumpur. |
| `STORAGE_BUCKET_NAME` | Owner rectification uploads. Use **Images**; the lowercase default does not match the existing bucket. Other upload paths hardcode Images. |
| `STRIPE_PUBLISHABLE_KEY` | PaymentSheet key; match the backend account and test/live mode. |
| `RESEND_FROM_EMAIL` | Sender authorised by the Resend account. |
| `RESEND_API_KEY` | Existing email service reads this in the client. Bundling exposes a server credential; move email delivery server-side before public distribution. |
| `GEMINI_API_KEY` | Optional OCR cloud-vision fallback. Do not assume OCR is mandatory for submissions or a bundled key is private. |
| `STRIPE_SECRET_KEY` | Legacy direct Stripe helpers still read this client setting. PaymentIntent creation uses the backend. Do not embed production secrets; migrate these helpers server-side before secure distribution. |

Other declared getters have no current application call sites: `APP_ENV`, `APP_NAME`, `APP_VERSION`, `AUTH_TOKEN_KEY`, `GOOGLE_CLIENT_SECRET`, `GOOGLE_CLIENT_ID_ANDROID`, `GOOGLE_CLIENT_ID_IOS`, `GPS_ACCURACY_THRESHOLD_METERS`, `MAX_PHOTO_UPLOAD_SIZE_MB`, `FCM_SENDER_ID`. Do not assume they configure every corresponding feature. Do not supply an OAuth client secret to the mobile app. `JWT_EXPIRATION_HOURS` is not consumed by current Dart code.

Optional integrations require their service configuration; leaving credentials unset does not make those features functional.

## Backend and integration setup

### Supabase

Obtain authorised access to the existing project from its maintainer. A new project requires a reviewed schema export, database function definitions, policies, Auth configuration and Edge Function source. **This checkout has no schema deployment package or payment function source, so cloning alone cannot recreate the backend.**

| Area | Public tables |
| --- | --- |
| Accounts | `users`, `user_devices` |
| Restaurants | `restaurants` |
| Reports | `complaints`, `complaint_issues`, `complaint_photos` |
| Compliance | `inspections`, `evidence`, `notices`, `rectifications` |
| Workflow | `workflow_states`, `workflow_steps` |
| Payments | `payments` |
| Notifications/history | `notifications`, `admin_action_logs`, `audit_logs`, `user_audit_logs` |

Backend routines include `save_inspection_record`, `finalize_inspection_case`, `settle_inspection_payment`, `handle_new_user` and `handle_user_password_sync`. Preserve signatures, schema relationships and triggers. Configure Realtime for subscribed tables if live updates are needed.

The inspected Storage bucket is **Images**, case sensitive and public. Core uploads generate public URLs. Profile code additionally attempts `avatars` and `banners`, absent from the inspected backend; those paths require matching bucket access or a reviewed code change.

Authentication combines Supabase Auth with custom `public.users` handling. Provision matching Auth/application profiles and correct roles for privileged accounts. A public user row alone does not guarantee a valid payment session. Obtain admin/government credentials privately; no passwords are included here.

### Stripe

The deployed function is **stripe-payment**. It references `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY`. Supabase supplies reserved values; configure payment secrets in the function environment, separate from Flutter. See [Supabase function secrets](https://supabase.com/docs/guides/functions/secrets).

Use matching test-mode keys for demonstrations. Verify the function, settlement routine, case ownership and Auth session before paying an issued fine. Webhook configuration/delivery requires separate verification. Editing mobile `.env` does not change hosted secrets. Do not manually mark fines paid to bypass errors.

### Maps, Google sign-in and Firebase

1. Follow [Google's Android Maps setup](https://developers.google.com/maps/documentation/android-sdk/get-api-key): enable Maps SDK, configure billing where required and restrict keys. Register package **com.example.colab** and the actual signing fingerprint.
2. Set the Maps key in `.env`; Android Gradle injects it into the manifest. Routing also uses Google's Directions endpoint and external OSRM fallbacks; working map rendering does not verify routing access.
3. Configure Android signing/package settings, Web OAuth client ID and the Supabase Google provider for Google login.
4. Supply the matching Firebase `android/app/google-services.json`. The tracked file belongs to the existing setup; replace it for your own project. Device permissions, registration and server delivery configuration are also necessary.
5. iOS needs macOS/Xcode and separate Maps, Firebase, permissions and sign-in configuration; its integrations were not validated here.

## Using the application

Use separate authorised accounts for the complete demonstration:

1. **Owner:** register/sign in; submit restaurant details, location, photo and SSM evidence.
2. **Admin:** review and approve a valid restaurant application.
3. **Customer:** discover the approved outlet, submit a complaint with required details/photo/location and follow complaint history.
4. **Admin:** review evidence. Location, timing, duplication and incomplete-data flags can block approval; a visible photo alone does not establish a passed check.
5. **Government:** schedule an inspection and record findings/photos.
6. **Admin and government:** admin reviews the inspection report; after approval, the officer issues the action/notice.
7. **Owner:** complete required payment and rectification actions through that notice. Evidence submission, acceptance, payment and closure are separate checklist states.
8. **Authority:** verify remaining requirements and close an eligible case. Refresh/reopen to confirm persistence; the owner can view the resolution report/PDF.

Customers can explore Recommendations, Risk Details and Risk Rankings. The real Google Maps screen is `lib/gps/screens/restaurant_map_screen.dart`. Recommendations use approved outlets/current evaluation and distance ordering. Rankings offer Today/Week and Platinum/Gold/Silver/Bronze filters.

Risk scores are application rules, not safety guarantees. Missing evidence can produce a baseline score. Week rankings use a current-data formula, not stored seven-day history. GPS fallback can make nearby results differ from actual device location.

## Checks and troubleshooting

Run `flutter analyze` after application changes. No automated test files were found in the inspected checkout. Build/analysis success does not validate hosted integrations; exercise role workflows, uploads, refresh/restart persistence and Stripe test payments separately.

| Problem | Check |
| --- | --- |
| Missing configuration | Correct root `.env` file/extension and required values; restart. |
| Blank map | Enabled APIs, billing/restrictions, package/signing fingerprint and rebuild. |
| Missing images/bucket | Exact Images bucket name, upload access, saved URL and object existence; profile buckets separately. |
| Inspection cannot save/close | Matching schema and required backend routines. |
| Payment configuration/session error | Backend secret, matching key mode, Auth session, case ownership and function logs. Never publish keys/tokens. |
| Google login fails | Web client ID, provider settings and installed build fingerprint. |
| No email/push | Sender/service configuration or Firebase/device permission/backend delivery respectively. |
| Stale data | Refresh, connectivity and reopening; synchronisation uses caches. Avoid deleting shared data as a troubleshooting shortcut. |

## Known limitations

- **Access control:** all 17 inspected public tables had Row Level Security disabled. Review ownership/role policies before deployment; enabling RLS without policies and authentication testing can break flows. No access rules were changed for this documentation.
- **Credentials/authentication:** direct email/legacy Stripe helpers and custom password handling require server-side hardening. Do not distribute production secrets in app assets.
- **Reproducibility:** schema migrations and Edge Function source are absent; obtain a backend package from the maintainer for independent setup.
- **Retention:** source implements seven-day local audit-cache cleanup at startup and periodically while running. This does not establish scheduled database/Storage deletion.
- **Legacy/platform code:** Android is the documented target. `lib/risk/screens/hygiene_heatmap_screen.dart` is a wireframe; use the main customer Map.

Documentation checked against application commit **8fae645**, matching GitHub main, and backend metadata on **20 September 2026**. No application behaviour was changed for this README.
