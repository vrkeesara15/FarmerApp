// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'core_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hindi (`hi`).
class CoreLocalizationsHi extends CoreLocalizations {
  CoreLocalizationsHi([String locale = 'hi']) : super(locale);

  @override
  String get appNameAgent => 'मित्र';

  @override
  String get appNameFarmer => 'किसान';

  @override
  String get splashTagline => 'आपके खेत के लिए भरोसेमंद सलाह';

  @override
  String get actionContinue => 'आगे बढ़ें';

  @override
  String get actionBack => 'पीछे';

  @override
  String get actionNext => 'अगला';

  @override
  String get actionRetry => 'फिर से कोशिश करें';

  @override
  String get actionCancel => 'रद्द करें';

  @override
  String get actionDone => 'हो गया';

  @override
  String get actionSkip => 'छोड़ें';

  @override
  String get actionClose => 'बंद करें';

  @override
  String get loading => 'लोड हो रहा है';

  @override
  String get languagePickerTitle => 'अपनी भाषा चुनें';

  @override
  String get languagePickerSubtitle => 'सुनने के लिए स्पीकर दबाएँ';

  @override
  String get languagePlayAudio => 'सुनें';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageTelugu => 'తెలుగు';

  @override
  String get languageKannada => 'ಕನ್ನಡ';

  @override
  String get languageHindi => 'हिन्दी';

  @override
  String get languageMarathi => 'मराठी';

  @override
  String get languageEnglishName => 'अंग्रेज़ी';

  @override
  String get languageTeluguName => 'तेलुगु';

  @override
  String get languageKannadaName => 'कन्नड़';

  @override
  String get languageHindiName => 'हिन्दी';

  @override
  String get languageMarathiName => 'मराठी';

  @override
  String get phoneLoginTitle => 'अपना मोबाइल नंबर डालें';

  @override
  String get phoneLabel => 'मोबाइल नंबर';

  @override
  String get phonePrefix => '+91';

  @override
  String get phoneHelper => 'हम SMS से 6 अंकों का OTP भेजेंगे';

  @override
  String get phoneInvalid => 'सही 10 अंकों का मोबाइल नंबर डालें';

  @override
  String get phoneSendOtp => 'OTP भेजें';

  @override
  String get otpTitle => 'OTP डालें';

  @override
  String otpSubtitle(String phone) {
    return '+91 $phone पर भेजा गया';
  }

  @override
  String get otpLabel => '6 अंकों का OTP';

  @override
  String get otpResend => 'OTP दोबारा भेजें';

  @override
  String otpResendIn(int seconds) {
    return '$seconds सेकंड में दोबारा भेजें';
  }

  @override
  String get otpInvalid => 'OTP गलत है। फिर से कोशिश करें।';

  @override
  String get otpVerify => 'जाँचें';

  @override
  String otpDigitLabel(int index) {
    return '6 में से $indexवाँ अंक';
  }

  @override
  String otpAttemptsLeft(int count) {
    return '$count कोशिशें बाकी';
  }

  @override
  String otpLocked(int minutes) {
    return 'बहुत बार गलत OTP डाला। $minutes मिनट बाद फिर कोशिश करें।';
  }

  @override
  String otpRateLimited(int minutes) {
    return 'बहुत बार OTP माँगा गया। $minutes मिनट बाद फिर कोशिश करें।';
  }

  @override
  String get otpExpired => 'यह OTP समाप्त हो गया है। नया माँगें।';

  @override
  String get phoneNotFound =>
      'यह नंबर पंजीकृत नहीं है। अपने मैनेजर से जोड़ने को कहें।';

  @override
  String get networkError =>
      'कनेक्शन नहीं है। नेटवर्क जाँचें और फिर कोशिश करें।';

  @override
  String get consentTitle => 'आपकी लोकेशन और डेटा';

  @override
  String get consentPoint1 => 'हम आपकी लोकेशन और विज़िट की फ़ोटो लेते हैं।';

  @override
  String get consentPoint2 => 'लोकेशन सिर्फ़ ड्यूटी के समय ली जाती है।';

  @override
  String get consentPoint3 =>
      'इसका उपयोग यात्रा भत्ते और विज़िट क्रेडिट के लिए होता है।';

  @override
  String get consentPoint4 =>
      'आपके मैनेजर और मालिक इसे देख सकते हैं। किसान नहीं।';

  @override
  String get consentAgree => 'मैं सहमत हूँ';

  @override
  String get consentPolicyLink => 'पूरी नीति पढ़ें';

  @override
  String get consentDataCardTitle =>
      'फ़सल की सलाह के लिए मेरा डेटा इस्तेमाल करें';

  @override
  String get consentDataCardBody =>
      'आपकी मदद के लिए हम आपकी फ़सल की फ़ोटो और खेत की जानकारी देखते हैं।';

  @override
  String get consentRequired => 'ज़रूरी';

  @override
  String get consentOffersCardTitle => 'मुझे ऑफ़र और सुझाव भेजें';

  @override
  String get consentOffersCardBody => 'उत्पादों और खेती के सुझावों के संदेश।';

  @override
  String get consentOptional => 'वैकल्पिक';

  @override
  String get consentReadAloud => 'पढ़कर सुनाएँ';

  @override
  String get dutyOn => 'ड्यूटी पर';

  @override
  String get dutyOff => 'ड्यूटी पर नहीं';

  @override
  String get dutyGoOn => 'ड्यूटी शुरू करें';

  @override
  String get dutyGoOff => 'ड्यूटी खत्म करें';

  @override
  String dutyElapsed(String duration) {
    return '$duration से ड्यूटी पर';
  }

  @override
  String get dutyLocationNote => 'लोकेशन सिर्फ़ ड्यूटी के समय चालू रहती है';

  @override
  String get syncSynced => 'सिंक हो गया';

  @override
  String syncPending(int count) {
    return '$count बाकी';
  }

  @override
  String get syncFailed => 'सिंक विफल';

  @override
  String get offlineBanner =>
      'आप ऑफ़लाइन हैं। आपका काम सेव है और बाद में सिंक होगा।';

  @override
  String get syncSyncing => 'सिंक हो रहा है…';

  @override
  String get syncDetailsTitle => 'सिंक विवरण';

  @override
  String get syncNow => 'अभी सिंक करें';

  @override
  String syncLastSync(String time) {
    return 'आख़िरी सिंक $time';
  }

  @override
  String get syncNeverSynced => 'अभी तक सिंक नहीं हुआ';

  @override
  String get syncAllDone => 'सब कुछ सिंक हो गया';

  @override
  String get syncAllDoneHelp =>
      'ऑफ़लाइन सहेजे गए नए किसान, खेत और फ़ोटो सर्वर तक पहुँचने तक यहाँ दिखेंगे।';

  @override
  String syncPendingSection(int count) {
    return 'सिंक की प्रतीक्षा में ($count)';
  }

  @override
  String syncFailedSection(int count) {
    return 'ध्यान देना ज़रूरी ($count)';
  }

  @override
  String get syncWaitingForPhoto => 'फ़ोटो अपलोड की प्रतीक्षा में';

  @override
  String syncPhotoUploads(int count) {
    return 'अपलोड हो रही फ़ोटो: $count';
  }

  @override
  String get syncTransportError =>
      'सर्वर से संपर्क नहीं हो सका। यह अपने आप फिर कोशिश करेगा।';

  @override
  String syncNextAttempt(String time) {
    return 'अगली कोशिश $time';
  }

  @override
  String syncItemTitle(String action, String entity) {
    return '$action $entity';
  }

  @override
  String get syncActionCreate => 'नया';

  @override
  String get syncActionUpdate => 'संपादित';

  @override
  String get syncActionDelete => 'हटाया गया';

  @override
  String get syncEntityFarmer => 'किसान';

  @override
  String get syncEntityFarm => 'खेत';

  @override
  String get syncEntityCropPlot => 'फ़सल प्लॉट';

  @override
  String get syncEntityConsent => 'सहमति';

  @override
  String get syncEntityOther => 'आइटम';

  @override
  String syncSavedAt(String time) {
    return 'सहेजा गया $time';
  }

  @override
  String get syncRejectedDefault =>
      'सर्वर ने यह आइटम स्वीकार नहीं किया। इसे संपादित करके फिर कोशिश करें।';

  @override
  String get syncRetryAll => 'सभी फिर कोशिश करें';

  @override
  String get syncDiscard => 'हटा दें';

  @override
  String get visitVerified => 'सत्यापित';

  @override
  String get visitPartial => 'आंशिक';

  @override
  String get visitUnverified => 'असत्यापित';

  @override
  String visitScore(int score) {
    return '100 में से $score अंक';
  }

  @override
  String visitDurationMinutes(int minutes) {
    return '$minutes मिनट';
  }

  @override
  String get visitPurposeAdvisory => 'सलाह';

  @override
  String get visitPurposeScouting => 'खेत निरीक्षण';

  @override
  String get visitPurposeDemo => 'डेमो';

  @override
  String get visitPurposeCollection => 'वसूली';

  @override
  String get visitPurposeSale => 'बिक्री';

  @override
  String get visitPurposeMeeting => 'बैठक';

  @override
  String get proofGeofence => 'खेत की सीमा के अंदर';

  @override
  String get proofGeofenceMissing => 'आप खेत की सीमा से बाहर थे';

  @override
  String get proofPhoto => 'फ़ोटो ली गई';

  @override
  String get proofPhotoMissing => 'विज़िट के दौरान फ़ोटो नहीं ली';

  @override
  String get proofFarmerConfirmed => 'किसान ने पुष्टि की';

  @override
  String get proofFarmerConfirmedMissing => 'किसान ने विज़िट की पुष्टि नहीं की';

  @override
  String get proofDuration => 'खेत पर न्यूनतम समय पूरा';

  @override
  String get proofDurationMissing => 'विज़िट 10 मिनट से कम थी';

  @override
  String get proofDone => 'पूरा';

  @override
  String get proofMissing => 'नहीं';

  @override
  String get cameraHoldSteady => 'स्थिर रखें';

  @override
  String get cameraGoodLight => 'अच्छी रोशनी';

  @override
  String get cameraFillFrame => 'फ़्रेम भरें';

  @override
  String get cameraLeafFrame => 'पत्ती को फ़्रेम के अंदर रखें';

  @override
  String get photoReviewHeading => 'अपनी फ़ोटो जाँचें';

  @override
  String photoReviewTitle(int index, int total) {
    return 'फ़ोटो $index / $total';
  }

  @override
  String get photoQualityOk => 'अच्छी फ़ोटो';

  @override
  String get photoQualityBlurry => 'धुंधली है';

  @override
  String get photoQualityDark => 'बहुत अंधेरा है';

  @override
  String get photoQualityChecking => 'फ़ोटो जाँच रहे हैं';

  @override
  String get photoTipBlurry =>
      'फ़ोन को स्थिर पकड़ें, पत्ते पर टैप करके फ़ोकस करें और फिर से लें';

  @override
  String get photoTipDark =>
      'अच्छी रोशनी में जाएँ, छाया से बाहर आएँ और फिर से लें';

  @override
  String get photoTipOk => 'फ़ोटो अच्छी है';

  @override
  String get photoRetake => 'फिर से लें';

  @override
  String get photoUse => 'यह फ़ोटो इस्तेमाल करें';

  @override
  String photoSizeKb(int kb) {
    return '$kb KB';
  }

  @override
  String photoDimensions(int width, int height) {
    return '$width × $height px';
  }

  @override
  String get confidenceHigh => 'उच्च भरोसा';

  @override
  String get confidenceMedium => 'मध्यम भरोसा';

  @override
  String get confidenceLow => 'अस्थायी';

  @override
  String get diagnosisSymptomsTitle => 'ये लक्षण जाँचें';

  @override
  String get diagnosisProvisionalNote =>
      'हमारे विशेषज्ञ 24 घंटे में पुष्टि करेंगे';

  @override
  String get diagnosisProblem => 'समस्या';

  @override
  String get treatmentOrganic => 'जैविक';

  @override
  String get treatmentChemical => 'रासायनिक';

  @override
  String get treatmentActiveIngredient => 'सक्रिय तत्व';

  @override
  String get treatmentDosePerAcre => 'प्रति एकड़';

  @override
  String get treatmentDosePerTank => 'प्रति 15 ली टंकी';

  @override
  String treatmentSafetyInterval(int days) {
    return 'कटाई से पहले $days दिन रुकें';
  }

  @override
  String get treatmentPpeGloves => 'दस्ताने';

  @override
  String get treatmentPpeMask => 'मास्क';

  @override
  String get treatmentPpeGoggles => 'चश्मा';

  @override
  String get treatmentPpeTitle => 'पहनें';

  @override
  String get ownBrand => 'अपना ब्रांड';

  @override
  String get productAdd => 'जोड़ें';

  @override
  String get productAdded => 'जोड़ा गया';

  @override
  String productStockAtStore(int count, String store) {
    return '$store में $count स्टॉक में';
  }

  @override
  String get productOutOfStock => 'स्टॉक नहीं';

  @override
  String get productPack => 'पैक';

  @override
  String cartItems(int count) {
    return '$count चीज़ें';
  }

  @override
  String get cartTotal => 'कुल';

  @override
  String get cartCheckout => 'भुगतान करें';

  @override
  String get paymentMethodTitle => 'आप कैसे भुगतान करेंगे?';

  @override
  String get paymentUpiQr => 'UPI QR';

  @override
  String get paymentUpiQrHint => 'स्कैन करके अभी भुगतान करें';

  @override
  String get paymentLink => 'भुगतान लिंक';

  @override
  String get paymentLinkHint => 'SMS या WhatsApp से भेजें';

  @override
  String get paymentCash => 'नकद';

  @override
  String get paymentCashHint => 'नकद लें और रसीद दें';

  @override
  String get paymentCredit => 'उधार';

  @override
  String get paymentCreditHint => 'किसान के खाते में जोड़ें';

  @override
  String get upiWaiting => 'भुगतान का इंतज़ार है';

  @override
  String get upiPaid => 'भुगतान मिल गया';

  @override
  String get upiFailed => 'भुगतान विफल';

  @override
  String upiExpiresIn(String time) {
    return '$time में समाप्त होगा';
  }

  @override
  String get upiAmount => 'राशि';

  @override
  String get upiScanHint => 'किसान से किसी भी UPI ऐप से स्कैन करने को कहें';

  @override
  String get upiRetry => 'नया QR दिखाएँ';

  @override
  String get khataBalance => 'बकाया राशि';

  @override
  String khataDueDate(String date) {
    return '$date तक देय';
  }

  @override
  String get khataDebit => 'दिया';

  @override
  String get khataCredit => 'मिला';

  @override
  String get khataNoEntries => 'अभी कोई प्रविष्टि नहीं';

  @override
  String get khataPayNow => 'अभी भुगतान करें';

  @override
  String get khataCollect => 'वसूल करें';

  @override
  String get emptyDefaultTitle => 'अभी यहाँ कुछ नहीं है';

  @override
  String get emptyDefaultHelp => 'जोड़ने के बाद चीज़ें यहाँ दिखेंगी।';

  @override
  String get errorTitle => 'कुछ गड़बड़ हो गई';

  @override
  String get errorHelp => 'कनेक्शन जाँचें और फिर कोशिश करें।';

  @override
  String get ratingTitle => 'अपनी विज़िट को रेटिंग दें';

  @override
  String get rating1 => 'बहुत खराब';

  @override
  String get rating2 => 'खराब';

  @override
  String get rating3 => 'ठीक';

  @override
  String get rating4 => 'अच्छा';

  @override
  String get rating5 => 'बहुत अच्छा';

  @override
  String stepperStepOf(int current, int total) {
    return '$total में से चरण $current';
  }

  @override
  String farmerLastVisit(String date) {
    return 'पिछली विज़िट $date';
  }

  @override
  String get farmerNoVisit => 'अभी कोई विज़िट नहीं';

  @override
  String farmerBalanceDue(String amount) {
    return 'बकाया $amount';
  }

  @override
  String get farmerVillage => 'गाँव';

  @override
  String get statTrendUp => 'बढ़ा';

  @override
  String get statTrendDown => 'घटा';

  @override
  String get statTrendFlat => 'कोई बदलाव नहीं';

  @override
  String get stageSowing => 'बुवाई';

  @override
  String get stageVegetative => 'बढ़वार';

  @override
  String get stageFlowering => 'फूल';

  @override
  String get stageFruiting => 'फल';

  @override
  String get stageHarvest => 'कटाई';

  @override
  String get settingsTheme => 'थीम';

  @override
  String get themeLight => 'लाइट';

  @override
  String get themeSunlight => 'धूप';

  @override
  String get settingsTitle => 'सेटिंग';

  @override
  String get settingsLanguage => 'भाषा';

  @override
  String get skeletonLoading => 'सामग्री लोड हो रही है';
}
