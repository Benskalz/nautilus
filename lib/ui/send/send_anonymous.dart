import 'dart:math';

import 'package:flutter/material.dart';
import 'package:wallet_flutter/styles.dart';
import 'package:wallet_flutter/ui/util/ui_util.dart';

class AnonymousAdvancedOptions extends StatefulWidget {
  const AnonymousAdvancedOptions({
    required this.onSendsChanged,
  });
  final Function(List<Map<String, dynamic>>) onSendsChanged;

  @override
  AnonymousAdvancedOptionsState createState() => AnonymousAdvancedOptionsState();
}

class AnonymousAdvancedOptionsState extends State<AnonymousAdvancedOptions> {
  bool _delays = true;

  List<Map<String, dynamic>> sends = [
    {'percent': 65, 'seconds': 0, 'percentController': TextEditingController()},
    {'percent': 32, 'seconds': 5, 'percentController': TextEditingController()},
  ];

  List<int> _numbersThatAddTo100(int n) {
    if (n <= 0) return [];

    final Random random = Random();
    final List<int> points = List.generate(n - 1, (_) => random.nextInt(101));

    points.add(0);
    points.add(100);
    points.sort();

    List<int> randomNumbers = List<int>.generate(n, (int i) => points[i + 1] - points[i]);
    return randomNumbers;
  }

  @override
  void initState() {
    super.initState();

    List<int> percentsThatAddTo100 = _numbersThatAddTo100(2);
    sends[0]['percent'] = percentsThatAddTo100[0];
    sends[1]['percent'] = percentsThatAddTo100[1];

    for (Map<String, dynamic> send in sends) {
      send['percentController'].text = send['percent'].toString();
    }
  }

  @override
  void dispose() {
    for (Map<String, dynamic> send in sends) {
      send['percentController'].dispose();
    }
    super.dispose();
  }

  Widget _buildSendInput(int index) {
    Map<String, dynamic> send = sends[index];
    return Row(
      children: <Widget>[
        Expanded(
          flex: 2,
          child: TextFormField(
            controller: send['percentController'] as TextEditingController,
            decoration: InputDecoration(
              suffixText: '%',
              suffixStyle: AppStyles.textStyleSettingItemSubheader(context),
            ),
            style: AppStyles.textStyleAddressPrimary(context),
            keyboardType: TextInputType.number,
            onChanged: (String value) {
              int? newPercent = int.tryParse(value);
              if (newPercent != null) {
                // Calculate new total percentage
                final int newTotal = sends.fold(
                    0,
                    (int sum, Map<String, dynamic> s) =>
                        sum + (s == sends[index] ? newPercent : s['percent'] as int));
                if (newTotal <= 100) {
                  setState(() {
                    send['percent'] = newPercent;
                  });
                  widget.onSendsChanged(sends);
                } else {
                  setState(() {
                    final int num = 100 - (newTotal - newPercent);
                    sends[index]['percent'] = num;
                    sends[index]['percentController'].text = num.toString();
                  });

                  // Revert change or handle error: show a Snackbar, alert dialog, etc.
                  UIUtil.showSnackbar('Total percentage cannot exceed 100%', context);
                  // Optionally, revert to the previous value if the new total exceeds 100
                  setState(() {});
                }
              }
              // widget.onSendsChanged(sends);
            },
          ),
        ),
        if (_delays) ...[
          SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: TextFormField(
              initialValue: sends[index]['seconds'].toString(),
              decoration: InputDecoration(
                suffixText: 'seconds',
                suffixStyle: AppStyles.textStyleSettingItemSubheader(context),
              ),
              style: AppStyles.textStyleAddressPrimary(context),
              keyboardType: TextInputType.number,
            ),
          ),
        ]
      ],
    );
  }

  void _addNewSend() {
    setState(() {
      sends.add({'percent': 0, 'seconds': 0, 'percentController': TextEditingController()});
      List<int> percentsThatAddTo100 = _numbersThatAddTo100(sends.length);
      for (int i = 0; i < sends.length; i++) {
        sends[i]['percent'] = percentsThatAddTo100[i];
        sends[i]['percentController'].text = percentsThatAddTo100[i].toString();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: [
              // add additional send button:
              IconButton(
                icon: Icon(Icons.add),
                onPressed: () {
                  _addNewSend();
                },
              ),
            ],
          ),

          CheckboxListTile(
            title: Text('Delays', style: AppStyles.textStyleSettingItemHeader(context)),
            value: _delays,
            onChanged: (bool? value) {
              setState(() {
                _delays = value!;
              });
            },
            controlAffinity: ListTileControlAffinity.leading,
          ),
          //   ],
          // ),
          // ...sends.map((Map<String, int> send) => _buildSendInput(send)).toList(),
          ...List<Widget>.generate(sends.length, (int index) => _buildSendInput(index)),
        ],
      ),
    );
  }
}
