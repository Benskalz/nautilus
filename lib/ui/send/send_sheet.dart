import 'dart:math';

import 'package:auto_size_text/auto_size_text.dart';
import 'package:event_taxi/event_taxi.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:decimal/decimal.dart';
import 'package:intl/intl.dart';
import 'package:keyboard_avoider/keyboard_avoider.dart';
import 'package:logger/logger.dart';
import 'package:manta_dart/manta_wallet.dart';
import 'package:manta_dart/messages.dart';

import 'package:nautilus_wallet_flutter/appstate_container.dart';
import 'package:nautilus_wallet_flutter/bus/fcm_update_event.dart';
import 'package:nautilus_wallet_flutter/bus/notification_setting_change_event.dart';
import 'package:nautilus_wallet_flutter/dimens.dart';
import 'package:nautilus_wallet_flutter/localization.dart';
import 'package:nautilus_wallet_flutter/model/available_currency.dart';
import 'package:nautilus_wallet_flutter/model/notification_settings.dart';
import 'package:nautilus_wallet_flutter/network/account_service.dart';
import 'package:nautilus_wallet_flutter/service_locator.dart';
import 'package:nautilus_wallet_flutter/app_icons.dart';
import 'package:nautilus_wallet_flutter/model/address.dart';
import 'package:nautilus_wallet_flutter/model/db/contact.dart';
import 'package:nautilus_wallet_flutter/model/db/user.dart';
import 'package:nautilus_wallet_flutter/model/db/appdb.dart';
import 'package:nautilus_wallet_flutter/styles.dart';
import 'package:nautilus_wallet_flutter/ui/receive/receive_sheet.dart';
import 'package:nautilus_wallet_flutter/ui/send/send_confirm_sheet.dart';
import 'package:nautilus_wallet_flutter/ui/request/request_confirm_sheet.dart';
import 'package:nautilus_wallet_flutter/ui/widgets/app_simpledialog.dart';
import 'package:nautilus_wallet_flutter/ui/widgets/app_text_field.dart';
import 'package:nautilus_wallet_flutter/ui/widgets/buttons.dart';
import 'package:nautilus_wallet_flutter/ui/widgets/dialog.dart';
import 'package:nautilus_wallet_flutter/ui/widgets/one_or_three_address_text.dart';
import 'package:nautilus_wallet_flutter/ui/util/formatters.dart';
import 'package:nautilus_wallet_flutter/ui/util/ui_util.dart';
import 'package:nautilus_wallet_flutter/ui/widgets/sheet_util.dart';
import 'package:nautilus_wallet_flutter/util/manta.dart';
import 'package:nautilus_wallet_flutter/util/numberutil.dart';
import 'package:nautilus_wallet_flutter/util/caseconverter.dart';
import 'package:nautilus_wallet_flutter/util/sharedprefsutil.dart';
import 'package:nautilus_wallet_flutter/util/user_data_util.dart';
import 'package:nautilus_wallet_flutter/themes.dart';
import 'package:qr_flutter/qr_flutter.dart';

class SendSheet extends StatefulWidget {
  final AvailableCurrency localCurrency;
  final Contact contact;
  final User user;
  final String address;
  final String quickSendAmount;

  SendSheet({@required this.localCurrency, this.contact, this.user, this.address, this.quickSendAmount}) : super();

  _SendSheetState createState() => _SendSheetState();
}

enum AddressStyle { TEXT60, TEXT90, PRIMARY }

class _SendSheetState extends State<SendSheet> {
  final Logger log = sl.get<Logger>();

  FocusNode _sendAddressFocusNode;
  FocusNode _sendAmountFocusNode;
  FocusNode _sendMemoFocusNode;
  TextEditingController _sendAddressController;
  TextEditingController _sendAmountController;
  TextEditingController _sendMemoController;

  // States
  AddressStyle _sendAddressStyle;
  String _amountHint = "";
  String _addressHint = "";
  String _memoHint = "";
  String _amountValidationText = "";
  String _addressValidationText = "";
  String _memoValidationText = "";
  String quickSendAmount;
  List<dynamic> _users;
  bool animationOpen;
  // Used to replace address textfield with colorized TextSpan
  bool _addressValidAndUnfocused = false;
  // Set to true when a username is being entered
  bool _isUser = false;
  // Buttons States (Used because we hide the buttons under certain conditions)
  bool _pasteButtonVisible = true;
  bool _showContactButton = true;
  // Local currency mode/fiat conversion
  bool _localCurrencyMode = false;
  String _lastLocalCurrencyAmount = "";
  String _lastCryptoAmount = "";
  NumberFormat _localCurrencyFormat;

  // Receive card instance
  ReceiveSheet receive;

  String _rawAmount;

  @override
  void initState() {
    super.initState();
    _sendAmountFocusNode = FocusNode();
    _sendAddressFocusNode = FocusNode();
    _sendMemoFocusNode = FocusNode();
    _sendAmountController = TextEditingController();
    _sendAddressController = TextEditingController();
    _sendMemoController = TextEditingController();
    _sendAddressStyle = AddressStyle.TEXT60;
    _users = List();
    quickSendAmount = widget.quickSendAmount;
    this.animationOpen = false;
    if (widget.user != null) {
      // Setup initial state for contact pre-filled
      _sendAddressController.text = "@" + widget.user.username;
      _isUser = true;
      _showContactButton = false;
      _pasteButtonVisible = false;
      _sendAddressStyle = AddressStyle.PRIMARY;
    } else if (widget.contact != null) {
      // Setup initial state for contact pre-filled
      _sendAddressController.text = "★" + widget.contact.name;
      _isUser = true;
      _showContactButton = false;
      _pasteButtonVisible = false;
      _sendAddressStyle = AddressStyle.PRIMARY;
    } else if (widget.address != null) {
      // Setup initial state with prefilled address
      _sendAddressController.text = widget.address;
      _showContactButton = false;
      _pasteButtonVisible = false;
      _sendAddressStyle = AddressStyle.TEXT90;
      _addressValidAndUnfocused = true;
    }
    // On amount focus change
    _sendAmountFocusNode.addListener(() {
      if (_sendAmountFocusNode.hasFocus) {
        if (_rawAmount != null) {
          setState(() {
            _sendAmountController.text = NumberUtil.getRawAsUsableString(_rawAmount).replaceAll(",", "");
            _rawAmount = null;
          });
        }
        if (quickSendAmount != null) {
          _sendAmountController.text = "";
          setState(() {
            quickSendAmount = null;
          });
        }
        setState(() {
          _amountHint = null;
        });
      } else {
        // if (_sendAmountController.text.isNotEmpty) {
        setState(() {
          _amountHint = "";
        });
        //
      }
    });
    // On address focus change
    _sendAddressFocusNode.addListener(() {
      if (_sendAddressFocusNode.hasFocus) {
        setState(() {
          _addressHint = null;
          _addressValidAndUnfocused = false;
          _pasteButtonVisible = true;
        });
        _sendAddressController.selection = TextSelection.fromPosition(TextPosition(offset: _sendAddressController.text.length));
        if (_sendAddressController.text.length > 0 && !_sendAddressController.text.startsWith("nano_")) {
          if (_sendAddressController.text.startsWith("@")) {
            sl.get<DBHelper>().getUsersWithNameLike(_sendAddressController.text.substring(1)).then((userList) {
              setState(() {
                _users = userList;
              });
            });
          } else if (_sendAddressController.text.startsWith("★")) {
            sl.get<DBHelper>().getContactsWithNameLike(_sendAddressController.text.substring(1)).then((userList) {
              setState(() {
                _users = userList;
              });
            });
          }
        }

        if (_sendAddressController.text.length == 0) {
          setState(() {
            _users = [];
          });
        }
      } else {
        if (_sendAddressController.text.length > 0) {
          sl.get<DBHelper>().getUserOrContactWithName(_sendAddressController.text.substring(1)).then((user) {
            if (user == null) {
              setState(() {
                _sendAddressStyle = AddressStyle.TEXT60;
              });
            } else {
              setState(() {
                _pasteButtonVisible = false;
                _sendAddressStyle = AddressStyle.PRIMARY;
              });
            }
          });
        }

        setState(() {
          _addressHint = "";
          _users = [];
          if (Address(_sendAddressController.text).isValid()) {
            _addressValidAndUnfocused = true;
          }
          if (_sendAddressController.text.length == 0) {
            _pasteButtonVisible = true;
          }
        });
        // if (_sendAddressController.text.trim() == "@" || _sendAddressController.text.trim() == "★") {
        //   _sendAddressController.text = "";
        //   setState(() {
        //     _showContactButton = true;
        //   });
        // }
      }
    });
    // On memo focus change
    _sendMemoFocusNode.addListener(() {
      if (_sendMemoFocusNode.hasFocus) {
        setState(() {
          _memoHint = null;
        });
      } else {
        setState(() {
          _memoHint = "";
        });
      }
    });

    // Set initial currency format
    _localCurrencyFormat = NumberFormat.currency(locale: widget.localCurrency.getLocale().toString(), symbol: widget.localCurrency.getCurrencySymbol());
    // Set quick send amount
    if (quickSendAmount != null) {
      _sendAmountController.text = NumberUtil.getRawAsUsableString(quickSendAmount).replaceAll(",", "");
    }
  }

  void _showMantaAnimation() {
    animationOpen = true;
    Navigator.of(context).push(AnimationLoadingOverlay(
        AnimationType.MANTA, StateContainer.of(context).curTheme.animationOverlayStrong, StateContainer.of(context).curTheme.animationOverlayMedium,
        onPoppedCallback: () => animationOpen = false));
  }

  Future<bool> showNotificationDialog() async {
    switch (await showDialog<NotificationOptions>(
        context: context,
        barrierColor: StateContainer.of(context).curTheme.barrier,
        builder: (BuildContext context) {
          return AppSimpleDialog(
            title: Text(
              AppLocalization.of(context).notifications,
              style: AppStyles.textStyleDialogHeader(context),
            ),
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 25.0),
                child: Text(AppLocalization.of(context).notificationInfo + "\n", style: AppStyles.textStyleParagraph(context)),
              ),
              AppSimpleDialogOption(
                onPressed: () {
                  Navigator.pop(context, NotificationOptions.ON);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(
                    AppLocalization.of(context).onStr,
                    style: AppStyles.textStyleDialogOptions(context),
                  ),
                ),
              ),
              AppSimpleDialogOption(
                onPressed: () {
                  Navigator.pop(context, NotificationOptions.OFF);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(
                    AppLocalization.of(context).off,
                    style: AppStyles.textStyleDialogOptions(context),
                  ),
                ),
              ),
            ],
          );
        })) {
      case NotificationOptions.ON:
        EventTaxiImpl.singleton().fire(NotificationSettingChangeEvent(isOn: true));
        FirebaseMessaging.instance.requestPermission();
        FirebaseMessaging.instance.getToken().then((fcmToken) {
          EventTaxiImpl.singleton().fire(FcmUpdateEvent(token: fcmToken));
        });
        return true;
      case NotificationOptions.OFF:
        EventTaxiImpl.singleton().fire(NotificationSettingChangeEvent(isOn: false));
        FirebaseMessaging.instance.getToken().then((fcmToken) {
          EventTaxiImpl.singleton().fire(FcmUpdateEvent(token: fcmToken));
        });
        return false;
      default:
        return false;
    }
  }

  Future<bool> showNeedNautilusUsernameAlert() async {
    switch (await showDialog<int>(
        context: context,
        barrierColor: StateContainer.of(context).curTheme.barrier,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text(
              AppLocalization.of(context).needUsernameAlertHeader,
              style: AppStyles.textStyleDialogHeader(context),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(AppLocalization.of(context).needUsernameAlert + "\n\n", style: AppStyles.textStyleParagraph(context)),
              ],
            ),
            actions: <Widget>[
              AppSimpleDialogOption(
                onPressed: () {
                  Navigator.pop(context, 2);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(
                    AppLocalization.of(context).goToQRCode,
                    style: AppStyles.textStyleDialogOptions(context),
                  ),
                ),
              ),
              AppSimpleDialogOption(
                onPressed: () {
                  Navigator.pop(context, 0);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(
                    AppLocalization.of(context).no,
                    style: AppStyles.textStyleDialogOptions(context),
                  ),
                ),
              ),
              AppSimpleDialogOption(
                onPressed: () {
                  Navigator.pop(context, 1);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(
                    AppLocalization.of(context).yes,
                    style: AppStyles.textStyleDialogOptions(context),
                  ),
                ),
              ),
            ],
          );
        })) {
      case 2:
        // go to qr code
        if (receive == null) {
          return false;
        }
        Navigator.of(context).pop();
        // TODO: BACKLOG: this is a roundabout solution to get the qr code to show up
        // probably better to do with an event bus
        Sheets.showAppHeightNineSheet(context: context, widget: receive);
        return true;
        break;
      case 1:
        // go to the username registration page:
        Navigator.of(context).pushNamed("/register_username");
        return true;
        break;
      case 0:
        // close the dialog:
        return false;
        break;
      default:
        return false;
        break;
    }
  }

  Future<void> showFallbackConnectedAlert() async {
    await showDialog<bool>(
        context: context,
        barrierColor: StateContainer.of(context).curTheme.barrier,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text(
              AppLocalization.of(context).fallbackHeader,
              style: AppStyles.textStyleDialogHeader(context),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(AppLocalization.of(context).fallbackInfo + "\n\n", style: AppStyles.textStyleParagraph(context)),
              ],
            ),
            actions: <Widget>[
              AppSimpleDialogOption(
                onPressed: () {
                  Navigator.pop(context, true);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(
                    AppLocalization.of(context).ok,
                    style: AppStyles.textStyleDialogOptions(context),
                  ),
                ),
              ),
            ],
          );
        });
  }

  void paintQrCode({String address}) {
    QrPainter painter = QrPainter(
      data: address == null ? StateContainer.of(context).wallet.address : address,
      version: 6,
      gapless: false,
      errorCorrectionLevel: QrErrorCorrectLevel.Q,
    );
    painter.toImageData(MediaQuery.of(context).size.width).then((byteData) {
      setState(() {
        receive = ReceiveSheet(
          localCurrency: StateContainer.of(context).curCurrency,
          address: StateContainer.of(context).wallet.address,
          qrWidget: Container(width: MediaQuery.of(context).size.width / 2.675, child: Image.memory(byteData.buffer.asUint8List())),
        );
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    // Create QR ahead of time because it improves performance this way
    if (receive == null && StateContainer.of(context).wallet != null) {
      paintQrCode();
    }
    // The main column that holds everything
    return SafeArea(
        minimum: EdgeInsets.only(bottom: MediaQuery.of(context).size.height * 0.035),
        child: Column(
          children: <Widget>[
            // A row for the header of the sheet, balance text and close button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                //Empty SizedBox
                SizedBox(
                  width: 60,
                  height: 60,
                ),

                // Container for the header, address and balance text
                Column(
                  children: <Widget>[
                    // Sheet handle
                    Container(
                      margin: EdgeInsets.only(top: 10),
                      height: 5,
                      width: MediaQuery.of(context).size.width * 0.15,
                      decoration: BoxDecoration(
                        color: StateContainer.of(context).curTheme.text10,
                        borderRadius: BorderRadius.circular(5.0),
                      ),
                    ),
                    Container(
                      margin: EdgeInsets.only(top: 15.0),
                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width - 140),
                      child: Column(
                        children: <Widget>[
                          // Header
                          AutoSizeText(
                            CaseChange.toUpperCase(AppLocalization.of(context).sendFrom, context),
                            style: AppStyles.textStyleHeader(context),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            stepGranularity: 0.1,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                //Empty SizedBox
                SizedBox(
                  width: 60,
                  height: 60,
                ),
              ],
            ),

            // account / wallet name:
            Container(
              margin: EdgeInsets.only(top: 10.0, left: 30, right: 30),
              child: Container(
                child: RichText(
                  textAlign: TextAlign.start,
                  text: TextSpan(
                    text: '',
                    children: [
                      TextSpan(
                        text: StateContainer.of(context).selectedAccount.name,
                        style: TextStyle(
                          color: StateContainer.of(context).curTheme.text60,
                          fontSize: 16.0,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'NunitoSans',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Address Text
            // Container(
            //   margin: EdgeInsets.symmetric(horizontal: 30),
            //   child: OneOrThreeLineAddressText(address: StateContainer.of(context).wallet.address, type: AddressTextType.PRIMARY60),
            // ),
            // Balance Text
            FutureBuilder(
              future: sl.get<SharedPrefsUtil>().getPriceConversion(),
              builder: (BuildContext context, AsyncSnapshot snapshot) {
                if (snapshot.hasData && snapshot.data != null && snapshot.data != PriceConversion.HIDDEN) {
                  return Container(
                    child: RichText(
                      textAlign: TextAlign.start,
                      text: TextSpan(
                        text: '',
                        children: [
                          TextSpan(
                            text: "(",
                            style: TextStyle(
                              color: StateContainer.of(context).curTheme.primary60,
                              fontSize: 14.0,
                              fontWeight: FontWeight.w100,
                              fontFamily: 'NunitoSans',
                            ),
                          ),
                          displayCurrencyAmount(
                            context,
                            TextStyle(
                              color: StateContainer.of(context).curTheme.primary60,
                              fontSize: 14.0,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'NunitoSans',
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                          TextSpan(
                            text: _localCurrencyMode
                                ? StateContainer.of(context)
                                    .wallet
                                    .getLocalCurrencyPrice(StateContainer.of(context).curCurrency, locale: StateContainer.of(context).currencyLocale)
                                : getCurrencySymbol(context) + StateContainer.of(context).wallet.getAccountBalanceDisplay(context),
                            style: TextStyle(
                              color: StateContainer.of(context).curTheme.primary60,
                              fontSize: 14.0,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'NunitoSans',
                            ),
                          ),
                          TextSpan(
                            text: ")",
                            style: TextStyle(
                              color: StateContainer.of(context).curTheme.primary60,
                              fontSize: 14.0,
                              fontWeight: FontWeight.w100,
                              fontFamily: 'NunitoSans',
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return Container(
                  child: Text(
                    "*******",
                    style: TextStyle(
                      color: Colors.transparent,
                      fontSize: 14.0,
                      fontWeight: FontWeight.w100,
                      fontFamily: 'NunitoSans',
                    ),
                  ),
                );
              },
            ),
            // A main container that holds everything
            Expanded(
              child: Container(
                margin: EdgeInsets.only(top: 5, bottom: 5),
                child: GestureDetector(
                  onTap: () {
                    // Clear focus of our fields when tapped in this empty space
                    _sendAddressFocusNode.unfocus();
                    _sendAmountFocusNode.unfocus();
                    _sendMemoFocusNode.unfocus();
                  },
                  child: KeyboardAvoider(
                    duration: Duration(milliseconds: 0),
                    autoScroll: true,
                    focusPadding: 40,
                    child: Column(
                      children: <Widget>[
                        Stack(
                          children: <Widget>[
                            // Column for Balance Text, Enter Amount container + Enter Amount Error container
                            Column(
                              children: <Widget>[
                                // ******* Enter Amount Container ******* //
                                getEnterAmountContainer(),
                                // ******* Enter Amount Container End ******* //

                                // ******* Enter Amount Error Container ******* //
                                Container(
                                  alignment: AlignmentDirectional(0, 0),
                                  margin: EdgeInsets.only(top: 3),
                                  child: Text(_amountValidationText,
                                      style: TextStyle(
                                        fontSize: 14.0,
                                        color: StateContainer.of(context).curTheme.primary,
                                        fontFamily: 'NunitoSans',
                                        fontWeight: FontWeight.w600,
                                      )),
                                ),
                                // ******* Enter Amount Error Container End ******* //
                              ],
                            ),

                            // Column for Enter Address container + Enter Address Error container
                            Column(
                              children: <Widget>[
                                Container(
                                  alignment: Alignment.topCenter,
                                  child: Stack(
                                    alignment: Alignment.topCenter,
                                    children: <Widget>[
                                      Container(
                                        margin:
                                            EdgeInsets.only(left: MediaQuery.of(context).size.width * 0.105, right: MediaQuery.of(context).size.width * 0.105),
                                        alignment: Alignment.bottomCenter,
                                        constraints: BoxConstraints(maxHeight: 160, minHeight: 0),
                                        // ********************************************* //
                                        // ********* The pop-up Contacts List ********* //
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(25),
                                          child: Container(
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(25),
                                              color: StateContainer.of(context).curTheme.backgroundDarkest,
                                            ),
                                            child: Container(
                                              decoration: BoxDecoration(
                                                borderRadius: BorderRadius.circular(25),
                                              ),
                                              margin: EdgeInsets.only(bottom: 50),
                                              child: ListView.builder(
                                                shrinkWrap: true,
                                                padding: EdgeInsets.only(bottom: 0, top: 0),
                                                itemCount: _users.length,
                                                itemBuilder: (context, index) {
                                                  return _buildUserItem(_users[index]);
                                                },
                                              ), // ********* The pop-up Contacts List End ********* //
                                              // ************************************************** //
                                            ),
                                          ),
                                        ),
                                      ),

                                      // ******* Enter Address Container ******* //
                                      getEnterAddressContainer(),
                                      // ******* Enter Address Container End ******* //
                                    ],
                                  ),
                                ),

                                // ******* Enter Address Error Container ******* //
                                Container(
                                  alignment: AlignmentDirectional(0, 0),
                                  margin: EdgeInsets.only(top: 3),
                                  child: Text(_addressValidationText,
                                      style: TextStyle(
                                        fontSize: 14.0,
                                        color: StateContainer.of(context).curTheme.primary,
                                        fontFamily: 'NunitoSans',
                                        fontWeight: FontWeight.w600,
                                      )),
                                ),
                                // ******* Enter Address Error Container End ******* //
                              ],
                            ),

                            // Column for Enter Memo container + Enter Memo Error container
                            Column(
                              children: <Widget>[
                                Container(
                                  alignment: Alignment.topCenter,
                                  child: Stack(
                                    alignment: Alignment.topCenter,
                                    children: <Widget>[
                                      Container(
                                        margin:
                                            EdgeInsets.only(left: MediaQuery.of(context).size.width * 0.105, right: MediaQuery.of(context).size.width * 0.105),
                                        alignment: Alignment.bottomCenter,
                                        constraints: BoxConstraints(maxHeight: 174, minHeight: 0),
                                      ),

                                      // ******* Enter Memo Container ******* //
                                      getEnterMemoContainer(),
                                      // ******* Enter Memo Container End ******* //
                                    ],
                                  ),
                                ),

                                // ******* Enter Memo Error Container ******* //
                                Container(
                                  alignment: AlignmentDirectional(0, 0),
                                  margin: EdgeInsets.only(top: 3),
                                  child: Text(_memoValidationText,
                                      style: TextStyle(
                                        fontSize: 14.0,
                                        color: StateContainer.of(context).curTheme.primary,
                                        fontFamily: 'NunitoSans',
                                        fontWeight: FontWeight.w600,
                                      )),
                                ),
                                // ******* Enter Memo Error Container End ******* //
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // A column for Enter Amount, Enter Address, Error containers and the pop up list
              ),
            ),

            //A column with "Scan QR Code" and "Send" buttons
            Container(
              child: Column(
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      // Send Button
                      AppButton.buildAppButton(context, AppButtonType.PRIMARY, AppLocalization.of(context).send, [27.0, 0.0, 7.0, 24.0], onPressed: () async {
                        bool validRequest = await _validateRequest();

                        if (!validRequest) {
                          return;
                        }

                        // verifyies the input is a user in the db
                        if (!_sendAddressController.text.startsWith("nano_")) {
                          // Need to make sure its a valid contact or user
                          sl.get<DBHelper>().getUserOrContactWithName(_sendAddressController.text.substring(1)).then((user) {
                            if (user == null) {
                              setState(() {
                                if (_sendAddressController.text.startsWith("★")) {
                                  _addressValidationText = AppLocalization.of(context).favoriteInvalid;
                                } else {
                                  _addressValidationText = AppLocalization.of(context).usernameInvalid;
                                }
                              });
                            } else {
                              Sheets.showAppHeightNineSheet(
                                  context: context,
                                  widget: SendConfirmSheet(
                                      amountRaw: _localCurrencyMode
                                          ? NumberUtil.getAmountAsRaw(_convertLocalCurrencyToCrypto())
                                          : _rawAmount == null
                                              ? (StateContainer.of(context).nyanoMode)
                                                  ? NumberUtil.getNyanoAmountAsRaw(_sendAmountController.text)
                                                  : NumberUtil.getAmountAsRaw(_sendAmountController.text)
                                              : _rawAmount,
                                      destination: user.address,
                                      contactName: (user is User)
                                          ? "@" + user.username
                                          : (user is Contact)
                                              ? "★" + user.name
                                              : null,
                                      maxSend: _isMaxSend(),
                                      localCurrency: _localCurrencyMode ? _sendAmountController.text : null,
                                      memo: _sendMemoController.text));
                            }
                          });
                        } else {
                          Sheets.showAppHeightNineSheet(
                              context: context,
                              widget: SendConfirmSheet(
                                  amountRaw: _localCurrencyMode
                                      ? NumberUtil.getAmountAsRaw(_convertLocalCurrencyToCrypto())
                                      : _rawAmount == null
                                          ? (StateContainer.of(context).curTheme is NyanTheme)
                                              ? NumberUtil.getNyanoAmountAsRaw(_sendAmountController.text)
                                              : NumberUtil.getAmountAsRaw(_sendAmountController.text)
                                          : _rawAmount,
                                  destination: _sendAddressController.text,
                                  maxSend: _isMaxSend(),
                                  localCurrency: _localCurrencyMode ? _sendAmountController.text : null,
                                  memo: _sendMemoController.text));
                        }
                      }),
                      // Request Button
                      AppButton.buildAppButton(context, AppButtonType.PRIMARY, AppLocalization.of(context).request, [7.0, 0.0, 27.0, 24.0],
                          onPressed: () async {
                        bool validRequest = await _validateRequest(isRequest: true);

                        if (!validRequest) {
                          return;
                        }
                        // verifyies the input is a user in the db
                        if (!_sendAddressController.text.startsWith("nano_")) {
                          // Need to make sure its a valid contact or user
                          var user = await sl.get<DBHelper>().getUserOrContactWithName(_sendAddressController.text.substring(1));
                          if (user == null) {
                            setState(() {
                              if (_sendAddressController.text.startsWith("★")) {
                                _addressValidationText = AppLocalization.of(context).favoriteInvalid;
                              } else {
                                _addressValidationText = AppLocalization.of(context).usernameInvalid;
                              }
                            });
                          } else {
                            Sheets.showAppHeightNineSheet(
                                context: context,
                                widget: RequestConfirmSheet(
                                  amountRaw: _localCurrencyMode
                                      ? NumberUtil.getAmountAsRaw(_convertLocalCurrencyToCrypto())
                                      : _rawAmount == null
                                          ? (StateContainer.of(context).nyanoMode)
                                              ? NumberUtil.getNyanoAmountAsRaw(_sendAmountController.text)
                                              : NumberUtil.getAmountAsRaw(_sendAmountController.text)
                                          : _rawAmount,
                                  destination: user.address,
                                  contactName: (user is User)
                                      ? "@" + user.username
                                      : (user is Contact)
                                          ? "★" + user.name
                                          : null,
                                  localCurrency: _localCurrencyMode ? _sendAmountController.text : null,
                                  memo: _sendMemoController.text,
                                ));
                          }
                        } else {
                          Sheets.showAppHeightNineSheet(
                              context: context,
                              widget: RequestConfirmSheet(
                                  amountRaw: _localCurrencyMode
                                      ? NumberUtil.getAmountAsRaw(_convertLocalCurrencyToCrypto())
                                      : _rawAmount == null
                                          ? (StateContainer.of(context).curTheme is NyanTheme)
                                              ? NumberUtil.getNyanoAmountAsRaw(_sendAmountController.text)
                                              : NumberUtil.getAmountAsRaw(_sendAmountController.text)
                                          : _rawAmount,
                                  destination: _sendAddressController.text,
                                  localCurrency: _localCurrencyMode ? _sendAmountController.text : null,
                                  memo: _sendMemoController.text));
                        }
                      }),
                    ],
                  ),
                  Row(
                    children: <Widget>[
                      // Scan QR Code Button
                      AppButton.buildAppButton(context, AppButtonType.PRIMARY_OUTLINE, AppLocalization.of(context).scanQrCode, Dimens.BUTTON_BOTTOM_DIMENS,
                          onPressed: () async {
                        UIUtil.cancelLockEvent();
                        String scanResult = await UserDataUtil.getQRData(DataType.MANTA_ADDRESS, context);
                        if (scanResult == null) {
                          UIUtil.showSnackbar(AppLocalization.of(context).qrInvalidAddress, context);
                        } else if (QRScanErrs.ERROR_LIST.contains(scanResult)) {
                          return;
                        } else if (MantaWallet.parseUrl(scanResult) != null) {
                          try {
                            _showMantaAnimation();
                            // Get manta payment request
                            MantaWallet manta = MantaWallet(scanResult);
                            PaymentRequestMessage paymentRequest = await MantaUtil.getPaymentDetails(manta);
                            if (animationOpen) {
                              Navigator.of(context).pop();
                            }
                            MantaUtil.processPaymentRequest(context, manta, paymentRequest);
                          } catch (e) {
                            if (animationOpen) {
                              Navigator.of(context).pop();
                            }
                            log.e('Failed to make manta request ${e.toString()}', e);
                            UIUtil.showSnackbar(AppLocalization.of(context).mantaError, context);
                          }
                        } else {
                          // Is a URI
                          Address address = Address(scanResult);
                          // See if this address belongs to a contact or username
                          dynamic user = await sl.get<DBHelper>().getUserOrContactWithAddress(address.address);
                          if (user != null) {
                            if (user is User) {
                              // Is a user
                              if (mounted) {
                                setState(() {
                                  _isUser = true;
                                  _addressValidationText = "";
                                  _sendAddressStyle = AddressStyle.PRIMARY;
                                  _pasteButtonVisible = false;
                                  _showContactButton = false;
                                });
                                _sendAddressController.text = "@" + user.username;
                              }
                            } else if (user is Contact) {
                              // Is a contact
                              if (mounted) {
                                setState(() {
                                  _isUser = true;
                                  _addressValidationText = "";
                                  _sendAddressStyle = AddressStyle.PRIMARY;
                                  _pasteButtonVisible = false;
                                  _showContactButton = false;
                                });
                                _sendAddressController.text = "★" + user.name;
                              }
                            }
                          } else {
                            // Not a contact or username
                            if (mounted) {
                              setState(() {
                                _isUser = false;
                                _addressValidationText = "";
                                _sendAddressStyle = AddressStyle.TEXT90;
                                _pasteButtonVisible = false;
                                _showContactButton = false;
                              });
                              _sendAddressController.text = address.address;
                              _sendAddressFocusNode.unfocus();
                              setState(() {
                                _addressValidAndUnfocused = true;
                              });
                            }
                          }
                          // If amount is present, fill it and go to SendConfirm
                          if (address.amount != null) {
                            bool hasError = false;
                            BigInt amountBigInt = BigInt.tryParse(address.amount);
                            if (amountBigInt != null && amountBigInt < BigInt.from(10).pow(24)) {
                              hasError = true;
                              UIUtil.showSnackbar(AppLocalization.of(context).minimumSend.replaceAll("%1", "0.000001"), context);
                            } else if (_localCurrencyMode && mounted) {
                              toggleLocalCurrency();
                              _sendAmountController.text = getRawAsThemeAwareAmount(context, address.amount);
                            } else if (mounted) {
                              setState(() {
                                _rawAmount = address.amount;
                                // If raw amount has more precision than we support show a special indicator
                                if ((StateContainer.of(context).nyanoMode)) {
                                  _sendAmountController.text = NumberUtil.getRawAsUsableString(_rawAmount).replaceAll(",", "");
                                } else {
                                  if (NumberUtil.getRawAsUsableString(_rawAmount).replaceAll(",", "") ==
                                      NumberUtil.getRawAsUsableDecimal(_rawAmount).toString()) {
                                    _sendAmountController.text = NumberUtil.getRawAsUsableString(_rawAmount).replaceAll(",", "");
                                  } else {
                                    _sendAmountController.text =
                                        NumberUtil.truncateDecimal(NumberUtil.getRawAsUsableDecimal(address.amount), digits: 6).toStringAsFixed(6) + "~";
                                  }
                                }
                              });
                              _sendAddressFocusNode.unfocus();
                            }
                            // If balance is sufficient go to SendConfirm
                            if (!hasError && StateContainer.of(context).wallet.accountBalance > amountBigInt) {
                              // Go to confirm sheet
                              Sheets.showAppHeightNineSheet(
                                  context: context,
                                  widget: SendConfirmSheet(
                                      amountRaw: _localCurrencyMode
                                          ? NumberUtil.getAmountAsRaw(_convertLocalCurrencyToCrypto())
                                          : _rawAmount == null
                                              ? NumberUtil.getAmountAsRaw(_sendAmountController.text)
                                              : _rawAmount,
                                      destination: user != null ? user.address : address.address,
                                      contactName: (user is User)
                                          ? "@" + user.username
                                          : (user is Contact)
                                              ? "★" + user.name
                                              : null,
                                      maxSend: _isMaxSend(),
                                      localCurrency: _localCurrencyMode ? _sendAmountController.text : null));
                            }
                          }
                        }
                      })
                    ],
                  ),
                ],
              ),
            ),
          ],
        ));
  }

  String _convertLocalCurrencyToCrypto() {
    String convertedAmt = _sendAmountController.text.replaceAll(",", ".");
    convertedAmt = NumberUtil.sanitizeNumber(convertedAmt);
    if (convertedAmt.isEmpty) {
      return "";
    }
    Decimal valueLocal = Decimal.parse(convertedAmt);
    Decimal conversion = Decimal.parse(StateContainer.of(context).wallet.localCurrencyConversion);
    return NumberUtil.truncateDecimal(valueLocal / conversion).toString();
  }

  String _convertCryptoToLocalCurrency() {
    String convertedAmt = NumberUtil.sanitizeNumber(_sendAmountController.text, maxDecimalDigits: 2);
    if (convertedAmt.isEmpty) {
      return "";
    }
    Decimal valueCrypto = Decimal.parse(convertedAmt);
    Decimal conversion = Decimal.parse(StateContainer.of(context).wallet.localCurrencyConversion);
    convertedAmt = NumberUtil.truncateDecimal(valueCrypto * conversion, digits: 2).toString();
    convertedAmt = convertedAmt.replaceAll(".", _localCurrencyFormat.symbols.DECIMAL_SEP);
    convertedAmt = _localCurrencyFormat.currencySymbol + convertedAmt;
    return convertedAmt;
  }

  // Determine if this is a max send or not by comparing balances
  bool _isMaxSend() {
    // Sanitize commas
    if (_sendAmountController.text.isEmpty) {
      return false;
    }
    try {
      String textField = _sendAmountController.text;
      String balance;
      if (_localCurrencyMode) {
        balance =
            StateContainer.of(context).wallet.getLocalCurrencyPrice(StateContainer.of(context).curCurrency, locale: StateContainer.of(context).currencyLocale);
      } else {
        balance = StateContainer.of(context).wallet.getAccountBalanceDisplay(context).replaceAll(r",", "");
      }
      // Convert to Integer representations
      int textFieldInt;
      int balanceInt;
      if (_localCurrencyMode) {
        // Sanitize currency values into plain integer representations
        textField = textField.replaceAll(",", ".");
        String sanitizedTextField = NumberUtil.sanitizeNumber(textField);
        balance = balance.replaceAll(_localCurrencyFormat.symbols.GROUP_SEP, "");
        balance = balance.replaceAll(",", ".");
        String sanitizedBalance = NumberUtil.sanitizeNumber(balance);
        textFieldInt = (Decimal.parse(sanitizedTextField) * Decimal.fromInt(pow(10, NumberUtil.maxDecimalDigits))).toInt();
        balanceInt = (Decimal.parse(sanitizedBalance) * Decimal.fromInt(pow(10, NumberUtil.maxDecimalDigits))).toInt();
      } else {
        textField = textField.replaceAll(",", "");
        textFieldInt = (Decimal.parse(textField) * Decimal.fromInt(pow(10, NumberUtil.maxDecimalDigits))).toInt();
        balanceInt = (Decimal.parse(balance) * Decimal.fromInt(pow(10, NumberUtil.maxDecimalDigits))).toInt();
      }
      return textFieldInt == balanceInt;
    } catch (e) {
      return false;
    }
  }

  void toggleLocalCurrency() {
    // Keep a cache of previous amounts because, it's kinda nice to see approx what nano is worth
    // this way you can tap button and tap back and not end up with X.9993451 NANO
    if (_localCurrencyMode) {
      // Switching to crypto-mode
      String cryptoAmountStr;
      // Check out previous state
      if (_sendAmountController.text == _lastLocalCurrencyAmount) {
        cryptoAmountStr = _lastCryptoAmount;
      } else {
        _lastLocalCurrencyAmount = _sendAmountController.text;
        _lastCryptoAmount = _convertLocalCurrencyToCrypto();
        cryptoAmountStr = _lastCryptoAmount;
      }
      setState(() {
        _localCurrencyMode = false;
      });
      Future.delayed(Duration(milliseconds: 50), () {
        _sendAmountController.text = cryptoAmountStr;
        _sendAmountController.selection = TextSelection.fromPosition(TextPosition(offset: cryptoAmountStr.length));
      });
    } else {
      // Switching to local-currency mode
      String localAmountStr;
      // Check our previous state
      if (_sendAmountController.text == _lastCryptoAmount) {
        localAmountStr = _lastLocalCurrencyAmount;
      } else {
        _lastCryptoAmount = _sendAmountController.text;
        _lastLocalCurrencyAmount = _convertCryptoToLocalCurrency();
        localAmountStr = _lastLocalCurrencyAmount;
      }
      setState(() {
        _localCurrencyMode = true;
      });
      Future.delayed(Duration(milliseconds: 50), () {
        _sendAmountController.text = localAmountStr;
        _sendAmountController.selection = TextSelection.fromPosition(TextPosition(offset: localAmountStr.length));
      });
    }
  }

  // Build contact items for the list
  Widget _buildUserItem(dynamic user) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          height: 42,
          width: double.infinity - 5,
          child: FlatButton(
            onPressed: () {
              _sendAddressController.text = (user is User) ? ("@" + user.username) : ("★" + user.name);
              _sendAddressFocusNode.unfocus();
              setState(() {
                _isUser = true;
                _showContactButton = false;
                _pasteButtonVisible = false;
                _sendAddressStyle = AddressStyle.PRIMARY;
              });
            },
            child: Text((user is User) ? user.username : user.name, textAlign: TextAlign.center, style: AppStyles.textStyleAddressPrimary(context)),
          ),
        ),
        Container(
          margin: EdgeInsets.symmetric(horizontal: 25),
          height: 1,
          color: StateContainer.of(context).curTheme.text03,
        ),
      ],
    );
  }

  /// Validate form data to see if valid
  /// @returns true if valid, false otherwise
  Future<bool> _validateRequest({bool isRequest = false}) async {
    bool isValid = true;
    _sendAmountFocusNode.unfocus();
    _sendAddressFocusNode.unfocus();
    _sendMemoFocusNode.unfocus();
    // Validate amount
    if (_sendAmountController.text.trim().isEmpty) {
      isValid = false;
      setState(() {
        _amountValidationText = AppLocalization.of(context).amountMissing;
      });
    } else {
      String bananoAmount = _localCurrencyMode
          ? _convertLocalCurrencyToCrypto()
          : _rawAmount == null
              ? _sendAmountController.text
              : NumberUtil.getRawAsUsableString(_rawAmount);
      BigInt balanceRaw = StateContainer.of(context).wallet.accountBalance;
      BigInt sendAmount = BigInt.tryParse(getThemeAwareAmountAsRaw(context, bananoAmount));
      if (sendAmount == null || sendAmount == BigInt.zero) {
        isValid = false;
        setState(() {
          _amountValidationText = AppLocalization.of(context).amountMissing;
        });
      } else if (sendAmount > balanceRaw && !isRequest) {
        isValid = false;
        setState(() {
          _amountValidationText = AppLocalization.of(context).insufficientBalance;
        });
      }
    }
    // Validate address
    bool isUser = _sendAddressController.text.startsWith("@");
    bool isFavorite = _sendAddressController.text.startsWith("★");
    bool isNano = _sendAddressController.text.startsWith("nano_");
    if (_sendAddressController.text.trim().isEmpty) {
      isValid = false;
      setState(() {
        _addressValidationText = AppLocalization.of(context).addressMissing;
        _pasteButtonVisible = true;
      });
    } else if (!isFavorite && !isUser && !Address(_sendAddressController.text).isValid()) {
      isValid = false;
      setState(() {
        _addressValidationText = AppLocalization.of(context).invalidAddress;
        _pasteButtonVisible = true;
      });
    } else if (!isUser && !isFavorite) {
      setState(() {
        _addressValidationText = "";
        _pasteButtonVisible = false;
      });
      _sendAddressFocusNode.unfocus();
    }
    if (isValid && isRequest) {
      // notifications must be turned on:
      bool notificationsEnabled = await sl.get<SharedPrefsUtil>().getNotificationsOn();
      if (!notificationsEnabled) {
        bool notificationTurnedOn = await showNotificationDialog();
        if (!notificationTurnedOn) {
          isValid = false;
        } else {
          // not sure why this is need to get it to update:
          await sl.get<SharedPrefsUtil>().setNotificationsOn(true);
        }
      }
      // still valid && you have to have a nautilus username to send requests:
      if (isValid && StateContainer.of(context).wallet.username == null) {
        isValid = false;
        await showNeedNautilusUsernameAlert();
      }

      if (isValid && sl.get<AccountService>().fallbackConnected) {
        isValid = false;
        await showFallbackConnectedAlert();
      }
    }
    return isValid;
  }

  //************ Enter Amount Container Method ************//
  //*******************************************************//
  getEnterAmountContainer() {
    return AppTextField(
      focusNode: _sendAmountFocusNode,
      controller: _sendAmountController,
      topMargin: 30,
      cursorColor: StateContainer.of(context).curTheme.primary,
      style: TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 16.0,
        color: StateContainer.of(context).curTheme.primary,
        fontFamily: 'NunitoSans',
      ),
      inputFormatters: _rawAmount == null
          ? [
              LengthLimitingTextInputFormatter(13),
              _localCurrencyMode
                  ? CurrencyFormatter(
                      decimalSeparator: _localCurrencyFormat.symbols.DECIMAL_SEP, commaSeparator: _localCurrencyFormat.symbols.GROUP_SEP, maxDecimalDigits: 2)
                  : CurrencyFormatter(maxDecimalDigits: NumberUtil.maxDecimalDigits),
              LocalCurrencyFormatter(active: _localCurrencyMode, currencyFormat: _localCurrencyFormat)
            ]
          : [LengthLimitingTextInputFormatter(13)],
      onChanged: (text) {
        // Always reset the error message to be less annoying
        setState(() {
          _amountValidationText = "";
          // Reset the raw amount
          _rawAmount = null;
        });
      },
      textInputAction: TextInputAction.next,
      maxLines: null,
      autocorrect: false,
      hintText: _amountHint == null ? "" : AppLocalization.of(context).enterAmount,
      prefixButton: _rawAmount == null
          ? TextFieldButton(
              icon: AppIcons.swapcurrency,
              onPressed: () {
                toggleLocalCurrency();
              },
            )
          : null,
      suffixButton: TextFieldButton(
        icon: AppIcons.max,
        onPressed: () {
          if (_isMaxSend()) {
            return;
          }
          if (!_localCurrencyMode) {
            _sendAmountController.text = StateContainer.of(context).wallet.getAccountBalanceDisplay(context).replaceAll(r",", "");
            _sendAmountController.selection = TextSelection.fromPosition(TextPosition(offset: _sendAmountController.text.length));
            _sendAddressController.selection = TextSelection.fromPosition(TextPosition(offset: _sendAddressController.text.length));
            // setState(() {
            //   // force max send button to fade out
            // });
            // FocusScope.of(context).unfocus();
            // if (!Address(_sendAddressController.text).isValid()) {
            //   FocusScope.of(context).requestFocus(_sendAddressFocusNode);
            // }
          } else {
            String localAmount = StateContainer.of(context)
                .wallet
                .getLocalCurrencyPrice(StateContainer.of(context).curCurrency, locale: StateContainer.of(context).currencyLocale);
            localAmount = localAmount.replaceAll(_localCurrencyFormat.symbols.GROUP_SEP, "");
            localAmount = localAmount.replaceAll(_localCurrencyFormat.symbols.DECIMAL_SEP, ".");
            localAmount = NumberUtil.sanitizeNumber(localAmount).replaceAll(".", _localCurrencyFormat.symbols.DECIMAL_SEP);
            _sendAmountController.text = _localCurrencyFormat.currencySymbol + localAmount;
            _sendAddressController.selection = TextSelection.fromPosition(TextPosition(offset: _sendAddressController.text.length));
          }
        },
      ),
      // fadeSuffixOnCondition: true,
      suffixShowFirstCondition: !_isMaxSend(),
      keyboardType: TextInputType.numberWithOptions(decimal: true),
      textAlign: TextAlign.center,
      onSubmitted: (text) {
        FocusScope.of(context).unfocus();
        if (!Address(_sendAddressController.text).isValid()) {
          FocusScope.of(context).requestFocus(_sendAddressFocusNode);
        }
      },
    );
  } //************ Enter Address Container Method End ************//
  //*************************************************************//

  //************ Enter Address Container Method ************//
  //*******************************************************//
  getEnterAddressContainer() {
    return AppTextField(
        topMargin: 115,
        padding: _addressValidAndUnfocused ? EdgeInsets.symmetric(horizontal: 25.0, vertical: 15.0) : EdgeInsets.zero,
        // padding: EdgeInsets.zero,
        textAlign: TextAlign.center,
        // textAlign: (_isUser || _sendAddressController.text.length == 0) ? TextAlign.center : TextAlign.start,
        focusNode: _sendAddressFocusNode,
        controller: _sendAddressController,
        cursorColor: StateContainer.of(context).curTheme.primary,
        inputFormatters: [
          _isUser ? LengthLimitingTextInputFormatter(20) : LengthLimitingTextInputFormatter(65),
        ],
        textInputAction: TextInputAction.done,
        maxLines: null,
        autocorrect: false,
        hintText: _addressHint == null ? "" : AppLocalization.of(context).enterUserOrAddress,
        prefixButton: TextFieldButton(
          icon: AppIcons.star,
          onPressed: () {
            if (_showContactButton && _users.length == 0) {
              // Show menu
              FocusScope.of(context).requestFocus(_sendAddressFocusNode);
              if (_sendAddressController.text.length == 0) {
                _sendAddressController.text = "★";
                _sendAddressController.selection = TextSelection.fromPosition(TextPosition(offset: _sendAddressController.text.length));
              }
              sl.get<DBHelper>().getContacts().then((userList) {
                setState(() {
                  _users = userList;
                });
              });
            }
          },
        ),
        fadePrefixOnCondition: true,
        prefixShowFirstCondition: _showContactButton && _users.length == 0,
        suffixButton: TextFieldButton(
          icon: AppIcons.paste,
          onPressed: () {
            if (!_pasteButtonVisible) {
              return;
            }
            Clipboard.getData("text/plain").then((ClipboardData data) {
              if (data == null || data.text == null) {
                return;
              }
              Address address = Address(data.text);
              if (address.isValid()) {
                sl.get<DBHelper>().getUserOrContactWithAddress(address.address).then((user) {
                  if (user == null) {
                    setState(() {
                      _isUser = false;
                      _addressValidationText = "";
                      _sendAddressStyle = AddressStyle.TEXT90;
                      _pasteButtonVisible = false;
                      _showContactButton = false;
                    });
                    _sendAddressController.text = address.address;
                    _sendAddressFocusNode.unfocus();
                    setState(() {
                      _addressValidAndUnfocused = true;
                    });
                  } else {
                    // Is a user
                    setState(() {
                      _isUser = true;
                      _addressValidationText = "";
                      _sendAddressStyle = AddressStyle.PRIMARY;
                      _pasteButtonVisible = false;
                      _showContactButton = false;
                    });
                    _sendAddressController.text = "@" + user.username;
                  }
                });
              }
            });
          },
        ),
        fadeSuffixOnCondition: true,
        suffixShowFirstCondition: _pasteButtonVisible,
        style: _sendAddressStyle == AddressStyle.TEXT60
            ? AppStyles.textStyleAddressText60(context)
            : _sendAddressStyle == AddressStyle.TEXT90
                ? AppStyles.textStyleAddressText90(context)
                : AppStyles.textStyleAddressPrimary(context),
        onChanged: (text) {
          bool isUser = text.startsWith("@");
          bool isFavorite = text.startsWith("★");
          bool isNano = text.startsWith("nano_");

          // prevent spaces:
          if (text.contains(" ")) {
            text = text.replaceAll(" ", "");
            _sendAddressController.text = text;
            _sendAddressController.selection = TextSelection.fromPosition(TextPosition(offset: _sendAddressController.text.length));
          }

          // remove the @ if it's the only text there:
          if (text == "@" || text == "★" || text == "nano_") {
            _sendAddressController.text = "";
            _sendAddressController.selection = TextSelection.fromPosition(TextPosition(offset: _sendAddressController.text.length));
            setState(() {
              _showContactButton = true;
              _pasteButtonVisible = true;
              _isUser = false;
              _users = [];
            });
            return;
          }

          if (text.length > 0) {
            setState(() {
              _showContactButton = false;
              if (!_addressValidAndUnfocused) {
                _pasteButtonVisible = true;
              }
            });
          } else {
            setState(() {
              _showContactButton = true;
              _pasteButtonVisible = true;
            });
          }
          // add the @ back in:
          if (text.length > 0 && !isUser && !isNano && !isFavorite) {
            // add @ to the beginning of the string:
            _sendAddressController.text = "@" + text;
            _sendAddressController.selection = TextSelection.fromPosition(TextPosition(offset: _sendAddressController.text.length));
            isUser = true;
          }

          if (text.length > 0 && text.startsWith("@nano_")) {
            setState(() {
              // remove the @ from the beginning of the string:
              _sendAddressController.text = text.replaceFirst("@nano_", "nano_");
              _sendAddressController.selection = TextSelection.fromPosition(TextPosition(offset: _sendAddressController.text.length));
              isUser = false;
            });
          }

          // check if it's a real nano address:
          // bool isUser = !text.startsWith("nano_") && !text.startsWith("★");
          if (text.length == 0) {
            setState(() {
              _isUser = false;
              _users = [];
            });
          } else if (isUser) {
            setState(() {
              _isUser = true;
            });
            sl.get<DBHelper>().getUserSuggestionsWithNameLike(text.substring(1)).then((matchedList) {
              setState(() {
                _users = matchedList;
              });
            });
          } else if (isFavorite) {
            setState(() {
              _isUser = true;
            });
            sl.get<DBHelper>().getContactsWithNameLike(text.substring(1)).then((matchedList) {
              setState(() {
                _users = matchedList;
              });
            });
          } else {
            setState(() {
              _isUser = false;
              _users = [];
            });
          }
          // Always reset the error message to be less annoying
          setState(() {
            _addressValidationText = "";
          });
          if (isNano && Address(text).isValid()) {
            _sendAddressFocusNode.unfocus();
            setState(() {
              _sendAddressStyle = AddressStyle.TEXT90;
              _addressValidationText = "";
              _pasteButtonVisible = false;
            });
          } else {
            setState(() {
              _sendAddressStyle = AddressStyle.TEXT60;
            });
            // } else {
            // sl.get<DBHelper>().getUserWithName(text.substring(1)).then((user) {
            //   if (user == null) {
            //     setState(() {
            //       _sendAddressStyle = AddressStyle.TEXT60;
            //     });
            //   } else {
            //     setState(() {
            //       _pasteButtonVisible = false;
            //       _sendAddressStyle = AddressStyle.PRIMARY;
            //     });
            //   }
            // });
          }
        },
        overrideTextFieldWidget: _addressValidAndUnfocused
            ? GestureDetector(
                onTap: () {
                  setState(() {
                    _addressValidAndUnfocused = false;
                  });
                  Future.delayed(Duration(milliseconds: 50), () {
                    FocusScope.of(context).requestFocus(_sendAddressFocusNode);
                  });
                },
                child: UIUtil.threeLineAddressText(context, _sendAddressController.text))
            : null);
  } //************ Enter Address Container Method End ************//
  //*************************************************************//

  //************ Enter Memo Container Method ************//
  //*******************************************************//
  getEnterMemoContainer() {
    double margin = 200;
    if (_sendAddressController.text.startsWith("nano_")) {
      if (_sendAddressController.text.length > 24) {
        margin = 217;
      }
      if (_sendAddressController.text.length > 48) {
        margin = 238;
      }
    }
    return AppTextField(
      topMargin: margin,
      padding: EdgeInsets.zero,
      textAlign: TextAlign.center,
      focusNode: _sendMemoFocusNode,
      controller: _sendMemoController,
      cursorColor: StateContainer.of(context).curTheme.primary,
      inputFormatters: [
        LengthLimitingTextInputFormatter(20),
      ],
      textInputAction: TextInputAction.done,
      maxLines: null,
      autocorrect: false,
      hintText: _memoHint == null ? "" : AppLocalization.of(context).enterMemo,
      fadeSuffixOnCondition: true,
      style: TextStyle(
        // fontWeight: FontWeight.w700,
        // fontSize: 16.0,
        // color: StateContainer.of(context).curTheme.primary,
        // fontFamily: 'NunitoSans',
        color: StateContainer.of(context).curTheme.text60,
        fontSize: AppFontSizes.small,
        height: 1.5,
        fontWeight: FontWeight.w100,
        fontFamily: 'OverpassMono',
      ),
      onChanged: (text) {
        // nothing for now
      },
    );
  } //************ Enter Memo Container Method End ************//
  //*************************************************************//
}
