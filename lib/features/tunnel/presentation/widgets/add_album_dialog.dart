import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';

class AddAlbumDialog extends StatefulWidget {
  final String? initialPath;
  const AddAlbumDialog({super.key, this.initialPath});

  @override
  State<AddAlbumDialog> createState() => _AddAlbumDialogState();
}

class _AddAlbumDialogState extends State<AddAlbumDialog> {
  final _formKey = GlobalKey<FormState>();

  // 1. Basic Info
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _folderPathController = TextEditingController();

  // 3. Classification
  final _tagsController = TextEditingController();

  // 4. Privacy Settings
  String _privacy = 'Shared with link';

  // 5. Additional Options
  bool _enableComments = true;
  bool _allowDownloads = true;
  bool _addWatermark = false;
  bool _passwordProtect = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialPath != null) {
      _folderPathController.text = widget.initialPath!;
      _nameController.text = widget.initialPath!.split(Platform.pathSeparator).last;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _folderPathController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _pickLocalFolder() async {
    final String? directoryPath = await getDirectoryPath();
    if (directoryPath != null) {
      setState(() {
        _folderPathController.text = directoryPath;
        if (_nameController.text.isEmpty) {
          _nameController.text = directoryPath
              .split(Platform.pathSeparator)
              .last;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: 600,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(32),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSectionHeader("1. THÔNG TIN CƠ BẢN"),
                      _buildTextField(
                        "Tên album",
                        _nameController,
                        hint: "Nhập tên album...",
                      ),
                      const SizedBox(height: 16),
                      _buildTextField(
                        "Mô tả album",
                        _descController,
                        isMultiline: true,
                        hint: "Nhập mô tả cho album này...",
                      ),
                      const SizedBox(height: 16),
                      _buildFolderPicker(),

                      const SizedBox(height: 32),
                      _buildSectionHeader("3. PHÂN LOẠI"),
                      _buildTextField(
                        "Tags",
                        _tagsController,
                        hint: "Ví dụ: vacation, beach, summer...",
                      ),

                      const SizedBox(height: 32),
                      _buildSectionHeader("4. CÀI ĐẶT QUYỀN RIÊNG TƯ"),
                      _buildPrivacyRadio(),

                      const SizedBox(height: 32),
                      _buildSectionHeader("5. TÙY CHỌN BỔ SUNG"),
                      _buildAdditionalOptions(),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),
            _buildActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.add_photo_alternate_rounded,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 16),
          const Text(
            "Thêm Album Mới",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(
        title,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
          fontSize: 12,
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller, {
    bool isMultiline = false,
    String? hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          maxLines: isMultiline ? 3 : 1,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
            filled: true,
            fillColor: Colors.grey.shade50,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.all(16),
          ),
        ),
      ],
    );
  }

  Widget _buildFolderPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Thư mục máy tính",
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _folderPathController,
                readOnly: true,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: "Chọn thư mục nguồn...",
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.all(16),
                ),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: _pickLocalFolder,
              icon: const Icon(Icons.folder_open_rounded, size: 18),
              label: const Text("Chọn folder"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                padding: const EdgeInsets.all(16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPrivacyRadio() {
    return RadioGroup<String>(
      groupValue: _privacy,
      onChanged: (v) => setState(() => _privacy = v!),
      child: Column(
        children: [
          _buildRadioItem(
            'Private',
            'Chỉ bạn xem được',
            Icons.lock_outline_rounded,
          ),
          _buildRadioItem(
            'Shared with link',
            'Ai có link đều xem được',
            Icons.link_rounded,
          ),
          _buildRadioItem(
            'Public',
            'Công khai cho mọi người',
            Icons.public_rounded,
          ),
        ],
      ),
    );
  }

  Widget _buildRadioItem(String value, String desc, IconData icon) {
    final isSelected = _privacy == value;
    return InkWell(
      onTap: () => setState(() => _privacy = value),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.05)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)
                : Theme.of(context).dividerColor.withValues(alpha: 0.1),
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                desc,
                style: TextStyle(
                  fontSize: 13,
                  color: isSelected ? Theme.of(context).colorScheme.onSurface : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ),
            Radio<String>(
              value: value,
              activeColor: Theme.of(context).colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdditionalOptions() {
    return Wrap(
      spacing: 24,
      runSpacing: 16,
      children: [
        _buildCheckbox(
          "Cho phép bình luận",
          _enableComments,
          (v) => setState(() => _enableComments = v!),
        ),
        _buildCheckbox(
          "Cho phép tải xuống",
          _allowDownloads,
          (v) => setState(() => _allowDownloads = v!),
        ),
        _buildCheckbox(
          "Thêm watermark",
          _addWatermark,
          (v) => setState(() => _addWatermark = v!),
        ),
        _buildCheckbox(
          "Bảo vệ mật khẩu",
          _passwordProtect,
          (v) => setState(() => _passwordProtect = v!),
        ),
      ],
    );
  }

  Widget _buildCheckbox(String label, bool value, Function(bool?) onChanged) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 24,
          height: 24,
          child: Checkbox(
            value: value,
            onChanged: onChanged,
            activeColor: Theme.of(context).colorScheme.primary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 13)),
      ],
    );
  }

  Widget _buildActions() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.1))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              "Hủy bỏ",
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 16),
          ElevatedButton(
            onPressed: () {
              if (_folderPathController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Vui lòng chọn thư mục nguồn")),
                );
                return;
              }
              Navigator.pop(context, {
                'name': _nameController.text.isEmpty
                    ? "Unnamed Album"
                    : _nameController.text,
                'path': _folderPathController.text,
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              "Tạo album mới",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
