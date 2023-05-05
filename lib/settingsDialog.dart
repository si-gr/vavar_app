import 'package:flutter/material.dart';

class SettingsDialog extends StatefulWidget {
  @override
  _SettingsDialogState createState() => _SettingsDialogState();

  Map settingsValues;
  SettingsDialog({super.key, required this.settingsValues});
}

class _SettingsDialogState extends State<SettingsDialog> {
  @override
  Widget build(BuildContext context) {
    List<Widget> textFields = [];
    widget.settingsValues.forEach((key, value) {
      textFields.add(TextField(
        keyboardType: TextInputType.number,
        onChanged: (value) {
          setState(() {
            try {
              widget.settingsValues[key] = double.parse(value);
            } on FormatException {
              widget.settingsValues[key] = -42;
            }
          });
        },
        decoration: InputDecoration(
          border: OutlineInputBorder(),
          labelText: "$key (${value})",
        ),
      ));
    });

    return AlertDialog(
      title: Text('Settings'),
      content: SizedBox(
        width: double.maxFinite,
        child: 
      ListView(padding: const EdgeInsets.all(8), children: textFields),),
      actions: <Widget>[
        TextButton(
          child: Text('Cancel'),
          onPressed: () {
            Navigator.of(context).pop(null);
          },
        ),
        TextButton(
          child: Text('Ok'),
          onPressed: () {
            Navigator.of(context).pop(widget.settingsValues);
          },
        ),
      ],
    );
  }
}
