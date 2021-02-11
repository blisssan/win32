import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

const ID_TEXT = 200;
const ID_EDITTEXT = 201;
const ID_PROGRESS = 202;

final hInstance = GetModuleHandle(nullptr);
String textEntered = '';

final monitors = <int>[];

int enumMonitorCallback(int hMonitor, int hDC, Pointer lpRect, int lParam) {
  monitors.add(hMonitor);
  return TRUE;
}

bool testBitmask(int bitmask, int value) => bitmask & value == value;

int findPrimaryMonitor(List<int> monitors) {
  final monitorInfo = calloc<MONITORINFO>()..ref.cbSize = sizeOf<MONITORINFO>();

  for (final monitor in monitors) {
    final result = GetMonitorInfo(monitor, monitorInfo);
    if (result == TRUE) {
      if (testBitmask(monitorInfo.ref.dwFlags, MONITORINFOF_PRIMARY)) {
        calloc.free(monitorInfo);
        return monitor;
      }
    }
  }

  calloc.free(monitorInfo);
  return 0;
}

void printMonitorCapabilities(int capabilitiesBitmask) {
  if (capabilitiesBitmask == MC_CAPS_NONE) {
    print(' - No capabilities supported');
  }
  if (testBitmask(capabilitiesBitmask, MC_CAPS_MONITOR_TECHNOLOGY_TYPE)) {
    print(' - Supports technology type functions');
  }
  if (testBitmask(capabilitiesBitmask, MC_CAPS_BRIGHTNESS)) {
    print(' - Supports brightness functions');
  }
  if (testBitmask(capabilitiesBitmask, MC_CAPS_CONTRAST)) {
    print(' - Supports contrast functions');
  }
  if (testBitmask(capabilitiesBitmask, MC_CAPS_COLOR_TEMPERATURE)) {
    print(' - Supports color temperature functions');
  }
}

void main() {
  var result = FALSE;

  result = EnumDisplayMonitors(
      NULL, // all displays
      nullptr, // no clipping region
      Pointer.fromFunction<MonitorEnumProc>(
          enumMonitorCallback, // dwData
          0),
      NULL);
  if (result == FALSE) {
    throw WindowsException(result);
  }

  print('Number of monitors: ${monitors.length}');

  final primaryMonitorHandle = findPrimaryMonitor(monitors);
  print('Primary monitor handle: $primaryMonitorHandle');

  final physicalMonitorCountPtr = calloc<Uint32>();
  result = GetNumberOfPhysicalMonitorsFromHMONITOR(
      primaryMonitorHandle, physicalMonitorCountPtr);
  if (result == FALSE) {
    print('No physical monitors attached.');
    calloc.free(physicalMonitorCountPtr);
    return;
  }

  print('Number of physical monitors: ${physicalMonitorCountPtr.value}');

  // We need to allocate space for a PHYSICAL_MONITOR struct for each physical
  // monitor. Each struct comprises a HANDLE and a 128-character UTF-16 array.
  // Since fixed-size arrays are difficult to allocate with Dart FFI at present,
  // and since we only need the first entry, we can manually allocate space of
  // the right size.
  final physicalMonitorArray =
      calloc<PHYSICAL_MONITOR>(physicalMonitorCountPtr.value);

  result = GetPhysicalMonitorsFromHMONITOR(primaryMonitorHandle,
      physicalMonitorCountPtr.value, physicalMonitorArray.cast());
  if (result == FALSE) {
    throw WindowsException(result);
  }
  // Retrieve the monitor handle for the first physical monitor in the returned
  // array.
  final physicalMonitorHandle = physicalMonitorArray.cast<IntPtr>().value;
  print('Physical monitor handle: $physicalMonitorHandle');
  final physicalMonitorDescription = physicalMonitorArray
      .elementAt(sizeOf<IntPtr>())
      .cast<Utf16>()
      .unpackString(128);
  print('Physical monitor description: $physicalMonitorDescription');

  DestroyPhysicalMonitors(
      physicalMonitorCountPtr.value, physicalMonitorArray.cast());

  // free all the heap-allocated variables
  calloc.free(physicalMonitorArray);
  calloc.free(physicalMonitorCountPtr);

  showDialog();
}

void showDialog() {
  // Allocate 2KB, which is more than enough space for the dialog in memory.
  final ptr = calloc<Uint16>(1024);
  var idx = 0;

  idx += ptr.elementAt(idx).cast<DLGTEMPLATE>().setDialog(
      style: WS_POPUP |
          WS_BORDER |
          WS_SYSMENU |
          DS_MODALFRAME |
          DS_SETFONT |
          WS_CAPTION,
      title: 'Sample dialog',
      cdit: 4,
      cx: 300,
      cy: 200,
      fontName: 'MS Shell Dlg',
      fontSize: 8);

  idx += ptr.elementAt(idx).cast<DLGITEMTEMPLATE>().setDialogItem(
      style: WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_DEFPUSHBUTTON,
      x: 100,
      y: 160,
      cx: 50,
      cy: 14,
      id: IDOK,
      windowSystemClass: 0x0080, // button
      text: 'OK');

  idx += ptr.elementAt(idx).cast<DLGITEMTEMPLATE>().setDialogItem(
      style: WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_PUSHBUTTON,
      x: 190,
      y: 160,
      cx: 50,
      cy: 14,
      id: IDCANCEL,
      windowSystemClass: 0x0080, // button
      text: 'Cancel');

  idx += ptr.elementAt(idx).cast<DLGITEMTEMPLATE>().setDialogItem(
      style: WS_CHILD | WS_VISIBLE,
      x: 10,
      y: 10,
      cx: 60,
      cy: 20,
      id: ID_TEXT,
      windowSystemClass: 0x0082, // static
      text: 'Some static wrapped text here.');

  idx += ptr.elementAt(idx).cast<DLGITEMTEMPLATE>().setDialogItem(
      style: PBS_SMOOTH | WS_BORDER | WS_VISIBLE,
      x: 6,
      y: 49,
      cx: 158,
      cy: 12,
      id: ID_PROGRESS,
      windowClass: 'msctls_progress32', // progress bar
      text: '');

  idx += ptr.elementAt(idx).cast<DLGITEMTEMPLATE>().setDialogItem(
      style: WS_CHILD | WS_VISIBLE | WS_TABSTOP | WS_BORDER,
      x: 20,
      y: 50,
      cx: 100,
      cy: 20,
      id: ID_EDITTEXT,
      windowSystemClass: 0x0081, // edit
      text: '');

  final lpDialogFunc = Pointer.fromFunction<DlgProc>(dialogReturnProc, 0);

  final nResult = DialogBoxIndirectParam(
      hInstance, ptr.cast<DLGTEMPLATE>(), NULL, lpDialogFunc, 0);

  if (nResult <= 0) {
    print('Error: $nResult');
  } else {
    print('Entered: $textEntered');
  }
  calloc.free(ptr);
}

// Documentation on this function here:
// https://docs.microsoft.com/en-us/windows/win32/dlgbox/using-dialog-boxes
int dialogReturnProc(int hwndDlg, int message, int wParam, int lParam) {
  switch (message) {
    case WM_INITDIALOG:
      {
        SendDlgItemMessage(hwndDlg, ID_PROGRESS, PBM_SETPOS, 35, 0);
        break;
      }
    case WM_COMMAND:
      {
        switch (LOWORD(wParam)) {
          case IDOK:
            print('OK');
            final textPtr = calloc<Uint16>(256).cast<Utf16>();
            GetDlgItemText(hwndDlg, ID_EDITTEXT, textPtr, 256);
            textEntered = textPtr.unpackString(256);
            calloc.free(textPtr);
            EndDialog(hwndDlg, wParam);
            return TRUE;
          case IDCANCEL:
            print('Cancel');
            EndDialog(hwndDlg, wParam);
            return TRUE;
        }
      }
  }

  return FALSE;
}
