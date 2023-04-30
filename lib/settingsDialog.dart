import 'package:flutter/material.dart';

class SettingsDialog extends StatefulWidget {
  @override
  _SettingsDialogState createState() => _SettingsDialogState();

  double val = 0;
  SettingsDialog();
}

class _SettingsDialogState extends State<SettingsDialog> {
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Settings'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text('Set the value'),
          Slider(
            value: widget.val,
            onChanged: (double value) {
              setState(() {
                widget.val = value;
              });
            },
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          child: Text('Cancel'),
          onPressed: () {
            Navigator.of(context).pop(widget.val);
          },
        ),
        TextButton(
          child: Text('Ok'),
          onPressed: () {
            Navigator.of(context).pop(widget.val);
          },
        ),
      ],
    );
  }
}