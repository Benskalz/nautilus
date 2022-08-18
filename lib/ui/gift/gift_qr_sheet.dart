import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:nautilus_wallet_flutter/appstate_container.dart';
import 'package:nautilus_wallet_flutter/dimens.dart';
import 'package:nautilus_wallet_flutter/generated/l10n.dart';
import 'package:nautilus_wallet_flutter/ui/receive/share_card.dart';
import 'package:nautilus_wallet_flutter/ui/util/formatters.dart';
import 'package:nautilus_wallet_flutter/ui/util/ui_util.dart';
import 'package:nautilus_wallet_flutter/ui/widgets/buttons.dart';
import 'package:nautilus_wallet_flutter/util/numberutil.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:share_plus/share_plus.dart';

class GiftQRSheet extends StatefulWidget {
  const GiftQRSheet({required this.link, required this.qrWidget}) : super();
  final Widget? qrWidget;
  final String link;

  GiftQRSheetStateState createState() => GiftQRSheetStateState();
}

class GiftQRSheetStateState extends State<GiftQRSheet> {
  GlobalKey? shareCardKey;
  ByteData? shareImageData;
  // Address copied items
  // Current state references
  bool _showShareCard = false;
  late bool _linkCopied;
  // Timer reference so we can cancel repeated events
  Timer? _linkCopiedTimer;

  Widget? qrWidget;

  Future<Uint8List?> _capturePng() async {
    if (shareCardKey != null && shareCardKey!.currentContext != null) {
      final RenderRepaintBoundary boundary = shareCardKey!.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final ui.Image image = await boundary.toImage(pixelRatio: 5.0);
      final ByteData byteData = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      return byteData.buffer.asUint8List();
    } else {
      return null;
    }
  }

  Future<Image?> getQRImage(String data) async {
    final PrettyQrCodePainter painter = PrettyQrCodePainter(
      data: data,
      errorCorrectLevel: QrErrorCorrectLevel.M,
      roundEdges: true,
      typeNumber: 9,
    );
    if (MediaQuery.of(context).size.width == 0) {
      return null;
    }

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final ui.Canvas canvas = Canvas(recorder);
    final double qrSize = MediaQuery.of(context).size.width;
    painter.paint(canvas, Size(qrSize, qrSize));
    final ui.Picture pic = recorder.endRecording();
    final ui.Image image = await pic.toImage(qrSize.toInt(), qrSize.toInt());
    final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return Image.memory(byteData!.buffer.asUint8List());
  }

  @override
  void initState() {
    super.initState();
    // Set initial state of copy button
    _linkCopied = false;
    // Create our SVG-heavy things in the constructor because they are slower operations
    // Share card initialization
    shareCardKey = GlobalKey();
    _showShareCard = false;

    qrWidget = widget.qrWidget;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
        minimum: EdgeInsets.only(bottom: MediaQuery.of(context).size.height * 0.035),
        child: Column(
          children: <Widget>[
            // A row for the address text and close button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                //Empty SizedBox
                const SizedBox(
                  width: 60,
                  height: 60,
                ),
                //Container for the address text and sheet handle
                Column(
                  children: <Widget>[
                    // Sheet handle
                    Container(
                      margin: const EdgeInsets.only(top: 10),
                      height: 5,
                      width: MediaQuery.of(context).size.width * 0.15,
                      decoration: BoxDecoration(
                        color: StateContainer.of(context).curTheme.text20,
                        borderRadius: BorderRadius.circular(5.0),
                      ),
                    ),
                  ],
                ),
                //Empty SizedBox
                const SizedBox(
                  width: 60,
                  height: 60,
                ),
              ],
            ),
            // QR which takes all the available space left from the buttons & address text
            Expanded(
              child: Padding(
                padding: const EdgeInsetsDirectional.only(top: 20, bottom: 28, start: 20, end: 20),
                child: LayoutBuilder(builder: (BuildContext context, BoxConstraints constraints) {
                  final double availableWidth = constraints.maxWidth;
                  final double availableHeight = (StateContainer.of(context).wallet?.username != null) ? (constraints.maxHeight - 70) : constraints.maxHeight;
                  const double widthDivideFactor = 1.3;
                  final double computedMaxSize = math.min(availableWidth / widthDivideFactor, availableHeight);
                  return Center(
                    child: Stack(
                      children: <Widget>[
                        if (_showShareCard)
                          Container(
                            alignment: AlignmentDirectional.center,
                            child: AppShareCard(
                              shareCardKey,
                              Center(
                                child: Transform.translate(
                                  offset: Offset.zero,
                                  child: ClipOval(
                                    child: Container(
                                      color: Colors.white,
                                      height: computedMaxSize,
                                      width: computedMaxSize,
                                      child: qrWidget,
                                    ),
                                  ),
                                ),
                              ),
                              const Image(image: AssetImage("assets/logo.png")),
                            ),
                          ),
                        // This is for hiding the share card
                        Center(
                          child: Container(
                            width: 260,
                            height: 150,
                            color: StateContainer.of(context).curTheme.backgroundDark,
                          ),
                        ),
                        // Background/border part the QR
                        // Center(
                        //   child: SizedBox(
                        //     width: computedMaxSize / 1.07,
                        //     height: computedMaxSize / 1.07,
                        //     child: SvgPicture.asset('legacy_assets/QR.svg'),
                        //   ),
                        // ),

                        // Background/border part the QR:
                        Center(
                          child: ClipOval(
                            child: Container(
                              color: Colors.white,
                              height: computedMaxSize,
                              width: computedMaxSize,
                              child: qrWidget,
                            ),
                          ),
                        ),

                        // Actual QR part of the QR
                        Center(
                          child: Container(
                            color: Colors.white,
                            padding: EdgeInsets.all(computedMaxSize / 51),
                            height: computedMaxSize / 1.53,
                            width: computedMaxSize / 1.53,
                            child: qrWidget,
                          ),
                        ),

                        // Outer ring
                        Center(
                          child: Container(
                            width: computedMaxSize,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: StateContainer.of(context).curTheme.primary!, width: computedMaxSize / 90),
                            ),
                          ),
                        ),
                        // Logo Background White
                        Center(
                          child: Container(
                            width: computedMaxSize / 5.5,
                            height: computedMaxSize / 5.5,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        // Logo Background Primary
                        Center(
                          child: Container(
                            width: computedMaxSize / 6.5,
                            height: computedMaxSize / 6.5,
                            decoration: const BoxDecoration(
                              color: /*StateContainer.of(context).curTheme.primary*/ Colors.black,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        Center(
                          child: SizedBox(
                            height: computedMaxSize / 8,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8.0),
                              child: const Image(image: AssetImage("assets/logo.png")),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ),
            ),

            //A column with Copy Address and Share Address buttons
            Column(
              children: <Widget>[
                Row(
                  children: <Widget>[
                    AppButton.buildAppButton(
                        context,
                        // Copy Address Button
                        _linkCopied ? AppButtonType.SUCCESS : AppButtonType.PRIMARY,
                        _linkCopied ? AppLocalization.of(context).linkCopied : AppLocalization.of(context).copyLink,
                        Dimens.BUTTON_COMPACT_LEFT_DIMENS, onPressed: () {
                      Clipboard.setData(ClipboardData(text: widget.link));
                      setState(() {
                        // Set copied style
                        _linkCopied = true;
                      });
                      if (_linkCopiedTimer != null) {
                        _linkCopiedTimer!.cancel();
                      }
                      _linkCopiedTimer = Timer(const Duration(milliseconds: 800), () {
                        if (mounted) {
                          setState(() {
                            _linkCopied = false;
                          });
                        }
                      });
                    }),
                    AppButton.buildAppButton(
                        context,
                        // Share Address Button
                        AppButtonType.PRIMARY_OUTLINE,
                        AppLocalization.of(context).shareLink,
                        Dimens.BUTTON_COMPACT_RIGHT_DIMENS, onPressed: () {
                      Share.share(widget.link);
                    }),
                  ],
                ),
              ],
            ),
          ],
        ));
  }
}
