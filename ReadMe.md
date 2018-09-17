*Update*: This bug is fixed in iOS 12.

# BugCoreBluetoothConnectivity
BugCoreBluetoothConnectivity demonstrates a CoreBluetooth bug that makes iOS 11.x get into a state where it can't connect to any nearby device. This affects all apps (i.e., it has nothing to do with the app). Once the device is in this state no app can connect to any peripheral including Apple devices like Apple TVs. The only way to fix it is to toggle Bluetooth from Settings.


## Build Requirements
+ Xcode 9.2 or later
+ iOS 11.0 SDK or later


## Runtime Requirements
+ 3 or more devices running iOS 11.0 or later


## Details
The app constantly scans and discovers peripherals with any advertised service. It shows them in a table view. The text color used in a table cell indicates the peripheral's connection state:

+ Black:=Disconnected
+ Orange:=Connecting
+ Green:=Connected

The app attempts to connect to the peripherals. If a connection is established then waits for a timeout to expire. After it expired the app cancels the connection, simulating that it has finished with it (e.g. has all data that it needs). Then waits for another timeout to expire and starts over.

Of course, repeated connection set ups and tear downs isn't a normal use case. That's the reason why it is *very* hard to reproduce this state during the development of a normal app.

### Steps to Reproduce:
1. Run the sample app on at least 3 iOS devices.
2. Wait for about a minute.

### Expected Results:
The devices can establish connections to each other periodically (You will see alternating black, orange and green rows).

### Actual Results:
After a minute or so some devices won't be able to connect to discovered peripherals. All peripherals in their list will be in connecting state (orange rows). However, if a nearby device connects to them then the connection is established (green row). If you suspect that a specific device has reached this state (where it can't connect to peripherals nearby) then turn off scanning (switch control top right) on all other devices where the app is running.

Once a device reaches this state it stays that way. Reinstalling the app doesn't fix the issue. Neither toggling Bluetooth from Control Center. Only if you toggle Bluetooth from Settings or reboot the device fixes the issue.

My main suspicion is that the problem surfaces when 2 devices try to connect to each other at the same time.
