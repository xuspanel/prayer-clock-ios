import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/clock_controller.dart';
import '../../transport/p4_transport.dart';
import '../theme/p4_theme.dart';

/// Tab 7: Files (`#t-files`, lines 375-412 & 1780-2061).
class FilesTab extends StatelessWidget {
  const FilesTab({super.key});

  Future<void> _onNewFolder(BuildContext context, ClockController ctrl) async {
    final name = await showP4PromptDialog(
      context,
      title: 'New folder name in ${ctrl.cwd}',
      hintText: 'Folder name',
    );
    if (name == null) return;
    await ctrl.createFolder(name);
  }

  Future<void> _onRename(BuildContext context, ClockController ctrl) async {
    final sel = ctrl.selectedPath;
    if (sel == null) return;
    final name = await showP4PromptDialog(
      context,
      title: 'New name',
      initialValue: baseName(sel),
    );
    if (name == null) return;
    await ctrl.renameSelectedFile(name);
  }

  Future<void> _onDelete(BuildContext context, ClockController ctrl) async {
    final sel = ctrl.selectedPath;
    if (sel == null) return;
    final ok = await showP4ConfirmDialog(
      context,
      title: 'Delete',
      message:
          'Delete $sel${ctrl.selectedIsDir ? ' and EVERYTHING inside it' : ''}?',
      confirmLabel: 'Delete',
    );
    if (ok) {
      await ctrl.deleteSelectedFile();
    }
  }

  Future<void> _onDownloadPath(
    BuildContext context,
    ClockController ctrl,
    String path,
  ) async {
    if (ctrl.dlBusy) {
      ctrl.showMsg('A download is already running - wait or press Cancel');
      return;
    }
    if (ctrl.upBusy || ctrl.fwBusy) {
      ctrl.showMsg('An upload is running - wait or press Cancel');
      return;
    }
    final size = ctrl.fsSizes[path] ?? 0;
    if (ctrl.mode == 'ble' && size > 1048576) {
      final ok = await showP4ConfirmDialog(
        context,
        title: 'Bluetooth Download',
        message:
            'Bluetooth transfer speed varies. Download ${formatSize(size)} over Bluetooth?',
        confirmLabel: 'Download',
        confirmColor: P4Colors.teal,
      );
      if (!ok) return;
    }
    await ctrl.downloadFile(path);
  }

  Future<void> _onUploadFiles(
    BuildContext context,
    ClockController ctrl,
  ) async {
    if (!ctrl.ready || ctrl.mode.isEmpty) {
      ctrl.showMsg('Unlock and connect first');
      return;
    }
    if (ctrl.anyTransferBusy) {
      ctrl.showMsg('Another transfer is running - wait or press Cancel');
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final items = <UploadItem>[];
    int totalBytes = 0;
    for (final f in result.files) {
      if (f.bytes != null) {
        items.add(UploadItem(name: f.name, bytes: f.bytes!));
        totalBytes += f.bytes!.length;
      }
    }
    if (items.isEmpty) return;

    if (ctrl.mode == 'ble' && totalBytes > 1048576 && context.mounted) {
      final ok = await showP4ConfirmDialog(
        context,
        title: 'Bluetooth Upload',
        message:
            'Bluetooth transfer speed varies. Upload ${formatSize(totalBytes)} over Bluetooth?',
        confirmLabel: 'Upload',
        confirmColor: P4Colors.teal,
      );
      if (!ok) return;
    }

    await ctrl.uploadFiles(items);
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<ClockController>();
    final sel = ctrl.selectedPath;
    final selIsAudio = sel != null && !ctrl.selectedIsDir && isAudioFile(sel);
    final String spaceStr = (ctrl.fsTotal != null && ctrl.fsUsed != null)
        ? '   (${formatSize(ctrl.fsTotal! - ctrl.fsUsed!)} free of ${formatSize(ctrl.fsTotal!)})'
        : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        P4Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '💾 SD card files',
                style: TextStyle(
                  color: P4Colors.teal,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Tap ⬇ next to a file to save it on this phone / PC.\nTap a file name for Play, Copy, Rename, Delete.',
                style: TextStyle(color: P4Colors.dim, fontSize: 14),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  P4Button(
                    key: const Key('btn_fs_up'),
                    label: '⬆ Up',
                    small: true,
                    color: P4Colors.slate,
                    onPressed: () => ctrl.loadFiles(parentPath(ctrl.cwd)),
                  ),
                  P4Button(
                    key: const Key('btn_fs_refresh'),
                    label: '↻',
                    small: true,
                    color: P4Colors.slate,
                    onPressed: () {
                      ctrl.loadFiles(ctrl.cwd);
                      ctrl.loadFsInfo();
                    },
                  ),
                  P4Button(
                    key: const Key('btn_fs_mkdir'),
                    label: '+ Folder',
                    small: true,
                    onPressed: () => _onNewFolder(context, ctrl),
                  ),
                  P4Button(
                    key: const Key('btn_fs_upload'),
                    label: '⬆ Upload files',
                    small: true,
                    onPressed: () => _onUploadFiles(context, ctrl),
                  ),
                  if (ctrl.clipboardPath != null)
                    P4Button(
                      key: const Key('btn_fs_paste'),
                      label:
                          'Paste "${baseName(ctrl.clipboardPath!)}"${ctrl.clipboardIsCut ? ' (move)' : ''}',
                      small: true,
                      color: P4Colors.orange,
                      onPressed: ctrl.pasteClipboard,
                    ),
                  if (ctrl.upBusy || ctrl.dlBusy)
                    P4Button(
                      key: const Key('btn_fs_cancel'),
                      label: 'Cancel',
                      small: true,
                      color: P4Colors.red,
                      onPressed: ctrl.cancelTransfer,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              RichText(
                text: TextSpan(
                  style: const TextStyle(fontSize: 15),
                  children: [
                    TextSpan(
                      text: ctrl.cwd,
                      style: const TextStyle(
                        color: P4Colors.text,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextSpan(
                      text: spaceStr,
                      style: const TextStyle(
                        color: P4Colors.dim,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              if (sel != null)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: P4Colors.bg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RichText(
                        text: TextSpan(
                          style: const TextStyle(
                            color: P4Colors.text,
                            fontSize: 14,
                          ),
                          children: [
                            const TextSpan(text: 'Selected: '),
                            TextSpan(
                              text: sel,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (selIsAudio)
                            P4Button(
                              key: const Key('btn_sel_play'),
                              label: '▶ Play',
                              small: true,
                              onPressed: ctrl.playSelectedFile,
                            ),
                          if (!ctrl.selectedIsDir)
                            P4Button(
                              key: const Key('btn_sel_download'),
                              label: '⬇ Download',
                              small: true,
                              onPressed: () =>
                                  _onDownloadPath(context, ctrl, sel),
                            ),
                          P4Button(
                            key: const Key('btn_sel_copy'),
                            label: 'Copy',
                            small: true,
                            color: P4Colors.slate,
                            onPressed: () => ctrl.setClipboard(cut: false),
                          ),
                          P4Button(
                            key: const Key('btn_sel_cut'),
                            label: 'Cut',
                            small: true,
                            color: P4Colors.slate,
                            onPressed: () => ctrl.setClipboard(cut: true),
                          ),
                          P4Button(
                            key: const Key('btn_sel_rename'),
                            label: 'Rename',
                            small: true,
                            color: P4Colors.slate,
                            onPressed: () => _onRename(context, ctrl),
                          ),
                          P4Button(
                            key: const Key('btn_sel_delete'),
                            label: 'Delete',
                            small: true,
                            color: P4Colors.red,
                            onPressed: () => _onDelete(context, ctrl),
                          ),
                          P4Button(
                            key: const Key('btn_sel_clear'),
                            label: '✕',
                            small: true,
                            color: P4Colors.slate,
                            onPressed: () => ctrl.selectFile(null),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              if (ctrl.transferProgress.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    ctrl.transferProgress,
                    key: const Key('text_transfer_progress'),
                    style: const TextStyle(
                      color: P4Colors.amber,
                      fontSize: 14,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 480),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    if (ctrl.cwd != '/')
                      InkWell(
                        onTap: () => ctrl.loadFiles(parentPath(ctrl.cwd)),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 4,
                          ),
                          decoration: const BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: P4Colors.slate),
                            ),
                          ),
                          child: const Text(
                            '📁 ..',
                            style: TextStyle(color: P4Colors.text, fontSize: 15),
                          ),
                        ),
                      ),
                    ...ctrl.fsDirs.map((dirName) {
                      final dirPath = joinPath(ctrl.cwd, dirName);
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 4,
                        ),
                        decoration: const BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: P4Colors.slate),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                onTap: () => ctrl.loadFiles(dirPath),
                                child: Text(
                                  '📁 $dirName',
                                  style: const TextStyle(
                                    color: P4Colors.text,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            ),
                            P4Button(
                              label: '⋯',
                              small: true,
                              color: P4Colors.slate,
                              onPressed: () =>
                                  ctrl.selectFile(dirPath, isDir: true),
                            ),
                          ],
                        ),
                      );
                    }),
                    ...ctrl.fsFiles.map((file) {
                      final filePath = joinPath(ctrl.cwd, file.name);
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 4,
                        ),
                        decoration: const BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: P4Colors.slate),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                onTap: () =>
                                    ctrl.selectFile(filePath, isDir: false),
                                child: Text(
                                  '📄 ${file.name}   (${formatSize(file.size)})',
                                  style: const TextStyle(
                                    color: P4Colors.text,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            ),
                            P4Button(
                              label: '⬇',
                              small: true,
                              color: P4Colors.slate,
                              onPressed: () =>
                                  _onDownloadPath(context, ctrl, filePath),
                            ),
                          ],
                        ),
                      );
                    }),
                    if (ctrl.fsDirs.isEmpty && ctrl.fsFiles.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          '(empty folder)',
                          style: TextStyle(color: P4Colors.dim, fontSize: 14),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

