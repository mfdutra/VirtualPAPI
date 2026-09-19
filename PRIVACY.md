# Privacy Policy for Virtual PAPI

**Last Updated: September 19, 2026**

## Overview

Virtual PAPI is a privacy-first aviation navigation application designed to do its work on your device. We are committed to protecting your privacy by not collecting, storing, or transmitting any personal information. The few network features the app has are described below.

## Data Collection

**We do not collect any data.** Virtual PAPI does not:
- Collect any personal information
- Track your location remotely
- Send analytics or usage statistics
- Use third-party tracking services
- Store data on external servers
- Require user accounts or authentication

## Location Data

Virtual PAPI uses your device's GPS to provide visual approach guidance. This location data:
- Remains entirely on your device
- Is never transmitted to external servers
- Is never stored persistently
- Is only used for real-time navigation calculations

The only exceptions are the optional map features described under Network Usage, which you trigger yourself. They share the location of the runway you selected (not your own position) with a map provider.

You can control location permissions through your device's Settings app at any time.

## Network Usage

Virtual PAPI does not need the internet for its core function: approach guidance works completely offline. The app uses the network only in the following cases.

**Receiving location from X-Plane or a GDL90 device (optional, off by default).** If you choose X-Plane or GDL90 as the location source in Settings, the app listens for UDP packets on your local network:
- X-Plane data is received on port 49002
- GDL90 data is received on ports 4000 and 43211
- This communication stays on your local network and does not go to the internet

**GDL90 discovery broadcast.** While GDL90 is the selected location source, the app sends a small broadcast packet on your local Wi-Fi network every 5 seconds, so that GDL90 devices can find it:
- The packet contains only the app name ("VirtualPAPI") and the port it listens on (4000)
- It contains no location data and no personal information
- It stays on your local network and is not sent to the internet

**Aviation database updates.** When you tap the button to update the aviation database in Settings, the app downloads the latest airport and runway data from virtualpapi.net:
- This only happens when you tap the button; the app never checks for updates on its own
- The request contains no personal information and no location data. It includes a short-lived code that proves the request comes from the app, and a version tag of the database you already have, so the server can skip the download if nothing has changed
- As with any internet request, the server can see your IP address and the time of the request. This is not used to identify or track you

**Map features (optional).** The Debug section of Settings has two map features that only run when you use them:
- "Destination in Google Maps" opens Google Maps (the app if installed, otherwise your web browser) at the coordinates of the runway aiming point you selected. From then on, Google's privacy policy applies
- "Destination Map" shows satellite imagery of the selected aiming point using Apple Maps, which loads map imagery for that area from Apple's servers. Apple's privacy policy applies

Neither feature sends your own current position.

## Third-Party Services

Virtual PAPI does not use any analytics platforms, advertising networks, or tracking services. The only third-party services the app can reach are Google Maps and Apple Maps, and only when you use the optional map features described above.

## Data Storage

All app data, including:
- Airport and runway information (pre-loaded database, optionally updated as described above)
- User preferences and settings
- Application state

is stored locally on your device. The app never synchronizes it to our servers or any other external server. Like other app data, it may be included in your device's own backups (for example, iCloud Backup) if you have them enabled.

## Children's Privacy

Virtual PAPI does not knowingly collect any information from anyone, including children under 13.

## Changes to This Policy

We may update this privacy policy from time to time. Any changes will be reflected in the app and on this page with an updated "Last Updated" date.

## Contact

If you have questions about this privacy policy, please contact:
- Developer: Marlon Dutra
- GitHub: https://github.com/mfdutra/VirtualPAPI

## Your Consent

By using Virtual PAPI, you consent to this privacy policy.

---

**Summary:** Virtual PAPI is a privacy-respecting application that does its work on your device. Your position never leaves your device, and we never collect any information about you. The app only goes online when you tap the database update button or use one of the optional map features, and it only talks to your local network when you choose X-Plane or GDL90 as the location source.
