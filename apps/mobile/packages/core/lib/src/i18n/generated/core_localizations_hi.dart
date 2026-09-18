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

  @override
  String get farmersTitle => 'किसान';

  @override
  String get farmersSearchHint => 'नाम, फ़ोन या गाँव खोजें';

  @override
  String get farmersAddFarmer => 'किसान जोड़ें';

  @override
  String get farmersEmptyTitle => 'अभी कोई किसान नहीं';

  @override
  String get farmersEmptyHelp =>
      'भेंट और ऑर्डर शुरू करने के लिए पहला किसान जोड़ें।';

  @override
  String get farmersNoResults => 'आपकी खोज से मेल खाता कोई किसान नहीं';

  @override
  String get farmersFilterVillage => 'गाँव';

  @override
  String get farmersFilterCrop => 'फ़सल';

  @override
  String get farmersFilterAll => 'सभी';

  @override
  String farmersCount(int count) {
    return '$count किसान';
  }

  @override
  String get farmerPendingSync => 'ऑनलाइन होने पर सिंक होगा';

  @override
  String get farmerPhoneUnverified => 'फ़ोन सत्यापित नहीं';

  @override
  String get farmerRejected => 'ध्यान चाहिए';

  @override
  String get regTitle => 'किसान जोड़ें';

  @override
  String get regStepBasics => 'किसान का विवरण';

  @override
  String get regStepBoundary => 'खेत की सीमा';

  @override
  String get regStepCrops => 'फ़सलें';

  @override
  String get regStepConsent => 'सहमति';

  @override
  String get regStepReview => 'जाँचें और सहेजें';

  @override
  String get regResumeDraft => 'जहाँ छोड़ा था वहीं से जारी';

  @override
  String get regDiscardDraft => 'ड्राफ़्ट हटाएँ';

  @override
  String get regFixIssues => 'आगे बढ़ने के लिए चिह्नित फ़ील्ड ठीक करें';

  @override
  String get regNameLabel => 'किसान का नाम';

  @override
  String get regNameHint => 'पहचान पत्र के अनुसार';

  @override
  String get regPhoneLabel => 'किसान का मोबाइल नंबर';

  @override
  String get regPhoneHelper => 'किसान को OTP भेजा जाएगा';

  @override
  String get regSendOtpToFarmer => 'किसान को OTP भेजें';

  @override
  String get regOtpSent => 'किसान को OTP भेजा गया। उनसे कोड पूछें।';

  @override
  String get regPhoneVerified => 'फ़ोन सत्यापित';

  @override
  String get regVerifyLater => 'बाद में सत्यापित करें';

  @override
  String get regVerifyLaterNote =>
      'सिग्नल नहीं? अभी सहेजें और किसान प्रोफ़ाइल से फ़ोन सत्यापित करें।';

  @override
  String get regVerifyLaterChosen => 'बाद में सत्यापित होगा';

  @override
  String get regDuplicatePhone => 'इस नंबर वाला किसान पहले से मौजूद है';

  @override
  String get regDuplicateOpen => 'मौजूदा किसान खोलें';

  @override
  String get regVillageLabel => 'गाँव';

  @override
  String get regVillageHint => 'गाँव चुनें';

  @override
  String get regVillageTyped => 'गाँव का नाम';

  @override
  String get regVillageNoneSynced =>
      'पहले सिंक के बाद गाँव लोड होंगे। अभी गाँव का नाम टाइप करें।';

  @override
  String get regLandmarkLabel => 'पहचान चिह्न';

  @override
  String get regLandmarkHint => 'मंदिर, स्कूल के पास…';

  @override
  String get regLanguageLabel => 'किसान की भाषा';

  @override
  String get regOwnershipLabel => 'ज़मीन';

  @override
  String get regBoundaryWalk => 'चारों ओर चलें';

  @override
  String get regBoundaryTap => 'कोने टैप करें';

  @override
  String get regStartWalk => 'चलना शुरू करें';

  @override
  String get regStopWalk => 'रोकें';

  @override
  String get regClosePolygon => 'सीमा बंद करें';

  @override
  String get regUndoPoint => 'बिंदु हटाएँ';

  @override
  String get regClearBoundary => 'साफ़ करें';

  @override
  String regPointsCount(int count) {
    return '$count बिंदु';
  }

  @override
  String regAccuracy(int metres) {
    return 'GPS सटीकता ±$metres मी';
  }

  @override
  String get regAccuracyWaiting => 'GPS की प्रतीक्षा…';

  @override
  String get regLocationOff => 'सीमा पर चलने के लिए लोकेशन चालू करें';

  @override
  String get regLocationDenied => 'सीमा पर चलने के लिए लोकेशन अनुमति चाहिए';

  @override
  String get regTapHint => 'नक्शे पर खेत के चारों कोने टैप करें';

  @override
  String get regWalkHint =>
      'खेत के किनारे-किनारे चलें। चलते हुए बिंदु जुड़ते जाएँगे।';

  @override
  String regComputedArea(String acres) {
    return 'मापा क्षेत्रफल $acres एकड़';
  }

  @override
  String get regAreaLabel => 'क्षेत्रफल एकड़ में';

  @override
  String get regAreaHint => 'जैसा किसान बताए';

  @override
  String get regUseMeasured => 'मापा हुआ लें';

  @override
  String get regAreaWarning =>
      'दर्ज क्षेत्रफल मापे गए क्षेत्रफल से 30% से अधिक अलग है। सहेजने से पहले जाँचें।';

  @override
  String get regBoundaryInvalid =>
      'सीमा खुद को काट रही है। आख़िरी बिंदु हटाकर फिर कोशिश करें।';

  @override
  String get regFarmNameLabel => 'खेत का नाम (वैकल्पिक)';

  @override
  String get regFarmNameHint => 'घर का खेत';

  @override
  String get regSoilLabel => 'मिट्टी का प्रकार';

  @override
  String get regIrrigationLabel => 'सिंचाई';

  @override
  String get regFarmPhoto => 'खेत की फ़ोटो (वैकल्पिक)';

  @override
  String get regTakePhoto => 'फ़ोटो लें';

  @override
  String get regPhotoAdded => 'फ़ोटो जोड़ी गई';

  @override
  String get regPhotoRemove => 'हटाएँ';

  @override
  String regFarmPhotosCount(int count) {
    return '$count फ़ोटो';
  }

  @override
  String get regCropsHelp => 'इस मौसम में इस खेत में उग रही हर फ़सल जोड़ें।';

  @override
  String get regAddCrop => 'फ़सल जोड़ें';

  @override
  String get regCropLabel => 'फ़सल';

  @override
  String get regVarietyLabel => 'किस्म';

  @override
  String get regVarietyHint => 'जैसे MTU-1010';

  @override
  String get regSowingDateLabel => 'बुवाई की तारीख़';

  @override
  String get regSowingDateHint => 'DD-MM-YYYY';

  @override
  String regSeasonAuto(String season) {
    return 'मौसम: $season';
  }

  @override
  String get regPlotAreaLabel => 'क्षेत्रफल (एकड़, वैकल्पिक)';

  @override
  String get regRemoveCrop => 'फ़सल हटाएँ';

  @override
  String regPlotTitle(int index) {
    return 'फ़सल $index';
  }

  @override
  String get regAddFarm => 'एक और खेत जोड़ें';

  @override
  String regFarmsCount(int count) {
    return '$count खेत';
  }

  @override
  String regFarmIndex(int index) {
    return 'खेत $index';
  }

  @override
  String get regConsentIntro => 'इसे किसान को उनकी भाषा में पढ़कर सुनाएँ।';

  @override
  String get regConsentNotice =>
      'फ़सल सलाह देने और भेंट का रिकॉर्ड रखने के लिए हम आपका नाम, फ़ोन, गाँव और खेत का विवरण रखेंगे। आप हमें कभी भी रोकने को कह सकते हैं।';

  @override
  String get regConsentMarketingNotice =>
      'आपकी अनुमति से हम SMS या WhatsApp पर ऑफ़र और खेती के सुझाव भी भेजेंगे।';

  @override
  String get regConsentGiven => 'किसान सहमत हैं';

  @override
  String get regReviewFarmer => 'किसान';

  @override
  String get regReviewFarms => 'खेत और फ़सलें';

  @override
  String get regReviewConsent => 'सहमति';

  @override
  String get regReviewSyncNote =>
      'अभी इस फ़ोन में सहेजा गया; नेटवर्क आने पर सर्वर को भेजा जाएगा।';

  @override
  String get regSave => 'किसान सहेजें';

  @override
  String get regSaveFarm => 'खेत सहेजें';

  @override
  String get regEdit => 'संपादित करें';

  @override
  String get regSaved => 'किसान सहेजा गया';

  @override
  String get regIssueName => 'किसान का नाम दर्ज करें';

  @override
  String get regIssuePhoneUnverified =>
      'फ़ोन सत्यापित करें या बाद में सत्यापित करें चुनें';

  @override
  String get regIssueVillage => 'गाँव चुनें';

  @override
  String get regIssueLanguage => 'किसान की भाषा चुनें';

  @override
  String get regIssueBoundary => 'सीमा के कम से कम 3 बिंदु चिह्नित करें';

  @override
  String get regIssueArea => 'क्षेत्रफल एकड़ में दर्ज करें';

  @override
  String get regIssueCrop => 'कम से कम एक फ़सल जोड़ें';

  @override
  String get regIssueSowingDate => 'हर फ़सल की बुवाई की तारीख़ दर्ज करें';

  @override
  String get regIssueConsent => 'पंजीकरण के लिए डेटा सहमति ज़रूरी है';

  @override
  String get soilBlack => 'काली मिट्टी';

  @override
  String get soilRed => 'लाल मिट्टी';

  @override
  String get soilSandy => 'रेतीली मिट्टी';

  @override
  String get soilLoamy => 'दोमट मिट्टी';

  @override
  String get soilClay => 'चिकनी मिट्टी';

  @override
  String get soilAlluvial => 'जलोढ़ मिट्टी';

  @override
  String get soilLaterite => 'लैटेराइट मिट्टी';

  @override
  String get irrigationRainfed => 'वर्षा आधारित';

  @override
  String get irrigationBorewell => 'बोरवेल';

  @override
  String get irrigationCanal => 'नहर';

  @override
  String get irrigationTank => 'तालाब';

  @override
  String get irrigationOpenWell => 'खुला कुआँ';

  @override
  String get irrigationDrip => 'ड्रिप';

  @override
  String get irrigationSprinkler => 'स्प्रिंकलर';

  @override
  String get ownershipOwn => 'अपनी';

  @override
  String get ownershipLeased => 'पट्टे पर';

  @override
  String get seasonKharif => 'ख़रीफ़';

  @override
  String get seasonRabi => 'रबी';

  @override
  String get seasonZaid => 'ज़ायद (गर्मी)';

  @override
  String get profileTabOverview => 'सारांश';

  @override
  String get profileTabVisits => 'भेंट';

  @override
  String get profileTabDiagnoses => 'निदान';

  @override
  String get profileTabOrders => 'ऑर्डर';

  @override
  String get profileTabKhata => 'खाता';

  @override
  String get profileStartVisit => 'भेंट शुरू करें';

  @override
  String get profileScout => 'फ़सल जाँच';

  @override
  String get profileNewOrder => 'नया ऑर्डर';

  @override
  String get profileCollect => 'वसूली';

  @override
  String get profileComingSoon => 'आगामी अपडेट में आएगा';

  @override
  String get profileVisitsEmpty => 'अभी कोई भेंट नहीं';

  @override
  String get profileDiagnosesEmpty => 'अभी कोई निदान नहीं';

  @override
  String get profileOrdersEmpty => 'अभी कोई ऑर्डर नहीं';

  @override
  String get profileKhataEmpty => 'अभी खाते में कोई प्रविष्टि नहीं';

  @override
  String get profilePhone => 'फ़ोन';

  @override
  String get profileLandmark => 'पहचान चिह्न';

  @override
  String get profileLanguage => 'भाषा';

  @override
  String get profileOwnership => 'ज़मीन';

  @override
  String get profileFarms => 'खेत';

  @override
  String profileAcres(String acres) {
    return '$acres एकड़';
  }

  @override
  String get profileAddFarm => 'खेत जोड़ें';

  @override
  String get profileEditFarm => 'खेत संपादित करें';

  @override
  String profileFarmPlots(int count) {
    return '$count फ़सलें';
  }

  @override
  String get profileNoFarms => 'अभी कोई खेत नहीं';

  @override
  String get profileDuplicateTitle => 'डुप्लिकेट — मिलाएँ?';

  @override
  String get profileDuplicateBody =>
      'सर्वर पर इस नंबर वाला किसान पहले से है। मौजूदा रिकॉर्ड खोलकर विवरण मिलाएँ।';

  @override
  String get profileRejectedTitle => 'सिंक अस्वीकृत';

  @override
  String get profileRejectedHelp =>
      'ठीक करके फिर कोशिश करने के लिए सिंक विवरण खोलें।';

  @override
  String get profileNotFound => 'किसान नहीं मिला';

  @override
  String get profileVerifyPhone => 'फ़ोन सत्यापित करें';

  @override
  String get consentGiven => 'दी गई';

  @override
  String get consentNotGiven => 'नहीं दी गई';

  @override
  String get farmEditTitle => 'खेत संपादित करें';

  @override
  String get farmAddTitle => 'खेत जोड़ें';

  @override
  String get mapNoBoundary => 'अभी कोई सीमा नहीं';

  @override
  String get mapAttribution => '© OpenStreetMap योगदानकर्ता';

  @override
  String get mapCurrentPosition => 'आपकी स्थिति';

  @override
  String mapCorner(int index) {
    return 'कोना $index';
  }

  @override
  String get mapFarmBoundary => 'खेत की सीमा';

  @override
  String get dutyNotificationTitle => 'ड्यूटी पर — लोकेशन चालू';

  @override
  String get dutyChannelName => 'ड्यूटी';

  @override
  String get dutyAlertsChannelName => 'ड्यूटी अलर्ट';

  @override
  String get dutyPromptTitle => 'अभी भी ड्यूटी पर हैं?';

  @override
  String dutyPromptBody(String time) {
    return '$time पर समाप्त होगी';
  }

  @override
  String get dutyEndedTitle => 'ड्यूटी समाप्त';

  @override
  String dutyAutoEndedBody(String time) {
    return 'आपका दिन $time पर अपने आप समाप्त हो गया।';
  }

  @override
  String get dutyServerEndedBody =>
      'सर्वर ने आपकी ड्यूटी समाप्त कर दी (निष्क्रियता या दिन का अंत)।';

  @override
  String dutyAutoEndAt(String time) {
    return '$time पर अपने आप समाप्त होगी';
  }

  @override
  String get dutyBlockedPolicy =>
      'ड्यूटी पर जाने के लिए लोकेशन नीति स्वीकार करें';

  @override
  String get dutyReviewPolicy => 'नीति देखें';

  @override
  String dutyPointsPending(int count) {
    return '$count पॉइंट अपलोड की प्रतीक्षा में';
  }

  @override
  String get dutyNoticeAlreadyActive =>
      'आप पहले से दूसरे डिवाइस पर ड्यूटी पर हैं। यह बंद ही रहेगा।';

  @override
  String get dutyNoticePolicy =>
      'ड्यूटी पर जाने से पहले वर्तमान लोकेशन नीति स्वीकार करें।';

  @override
  String get dutyNoticeLocationUnavailable =>
      'आपकी लोकेशन नहीं मिल सकी। लोकेशन चालू करके फिर कोशिश करें।';

  @override
  String get integrityBanner =>
      'कुछ डिवाइस जाँचों में समस्या मिली; विज़िट की समीक्षा हो सकती है।';

  @override
  String get disclosureIntro =>
      'शुरू करने से पहले, यहाँ बताया गया है कि मित्र क्या दर्ज करता है और क्यों।';

  @override
  String disclosureVersion(String version) {
    return 'नीति संस्करण $version';
  }

  @override
  String get disclosureUpdated =>
      'लोकेशन नीति बदल गई है। कृपया नया संस्करण पढ़कर स्वीकार करें।';

  @override
  String get policySheetTitle => 'लोकेशन नीति';

  @override
  String get locationPolicyText =>
      'मित्र लोकेशन नीति (संस्करण 2026-09-v1)\n\n1. हम क्या इकट्ठा करते हैं। जब आप ड्यूटी पर होते हैं, मित्र आपकी लोकेशन (अक्षांश, देशांतर, सटीकता, गति, दिशा), समय, बैटरी स्तर और बुनियादी डिवाइस जाँचें (मॉक लोकेशन, रूटेड डिवाइस, घड़ी का अंतर) दर्ज करता है। विज़िट के दौरान ली गई फ़ोटो, नोट और किसान की पुष्टि भी दर्ज होती है।\n\n2. केवल ड्यूटी पर। लोकेशन तभी दर्ज होती है जब आप ड्यूटी चालू करते हैं; ड्यूटी बंद करते ही, संस्था के तय समय पर दिन समाप्त होने पर (डिफ़ॉल्ट 20:00) या घर पर 60 मिनट निष्क्रिय रहने पर यह रुक जाती है। ड्यूटी बंद होने पर कुछ भी दर्ज नहीं होता, और लोकेशन चालू रहने तक एक सूचना हमेशा दिखती है।\n\n3. हम इसे क्यों इकट्ठा करते हैं। आपके ट्रैक से यात्रा भत्ते के किलोमीटर की गणना होती है, और विज़िट पर आपकी लोकेशन से उस विज़िट का क्रेडिट मिलता है। ट्रैक नहीं तो स्वचालित यात्रा भत्ता नहीं और सत्यापित विज़िट नहीं।\n\n4. इसे कौन देख सकता है। आपके क्लस्टर हेड, निदेशक और संस्था के मालिक अपने क्षेत्र के लिए आपका ट्रैक और विज़िट देख सकते हैं, और ऑडिटर फ़्लैग की गई विज़िट की समीक्षा कर सकते हैं। स्टोर मैनेजर और किसान आपकी लोकेशन कभी नहीं देखते। कच्चे पॉइंट 180 दिन रखे जाते हैं और फिर दैनिक योग में बदल दिए जाते हैं।';

  @override
  String get permissionsTitle => 'मित्र को चाहिए ये अनुमतियाँ';

  @override
  String get permissionsIntro =>
      'मित्र इन्हें एक-एक करके माँगेगा। इन्हें बाद में सेटिंग्स में बदल सकते हैं।';

  @override
  String get permLocationTitle => 'लोकेशन';

  @override
  String get permLocationBody =>
      'ड्यूटी पर आपका ट्रैक दर्ज करने और यह जाँचने के लिए कि आप खेत पर हैं।';

  @override
  String get permBackgroundTitle => 'लोकेशन हर समय';

  @override
  String get permBackgroundBody =>
      '\"हर समय अनुमति दें\" चुनें ताकि स्क्रीन बंद होने पर भी ट्रैकिंग चलती रहे। फिर भी यह केवल ड्यूटी पर ही चलती है।';

  @override
  String get permCameraTitle => 'कैमरा';

  @override
  String get permCameraBody =>
      'ऐप के अंदर ली गई खेत और विज़िट की फ़ोटो के लिए।';

  @override
  String get permNotificationsTitle => 'सूचनाएँ';

  @override
  String get permNotificationsBody =>
      'ड्यूटी की सूचना दिखाने और ड्यूटी खत्म होने से पहले याद दिलाने के लिए।';

  @override
  String get permGranted => 'अनुमति दी गई';

  @override
  String get permDenied => 'अनुमति नहीं';

  @override
  String get permOpenSettings => 'सेटिंग्स खोलें';

  @override
  String get permAllow => 'अनुमति दें';

  @override
  String get registeredTitle => 'डिवाइस पंजीकृत';

  @override
  String get registeredBody =>
      'आप तैयार हैं। दिन शुरू करने के लिए होम से ड्यूटी पर जाएँ।';

  @override
  String get registeredStart => 'होम पर जाएँ';

  @override
  String get homeTitle => 'होम';

  @override
  String get homeTodayStats => 'आज';

  @override
  String get statVisitsVerified => 'सत्यापित विज़िट';

  @override
  String get statFarmersAdded => 'जोड़े गए किसान';

  @override
  String get statCollections => 'वसूली';

  @override
  String get homeNextUp => 'अगला';

  @override
  String get homeNextUpEmpty => 'अभी कोई बीट प्लान नहीं';

  @override
  String get homeNextUpEmptyHelp =>
      'आपके क्लस्टर हेड गाँव सौंपेंगे। तब तक किसान जोड़ें और विज़िट शुरू करें।';

  @override
  String get homeQuickActions => 'त्वरित कार्य';

  @override
  String get actionStartVisit => 'विज़िट शुरू करें';

  @override
  String get actionScoutCrop => 'फ़सल जाँचें';

  @override
  String get actionCollectPayment => 'भुगतान लें';

  @override
  String get comingSoon => 'जल्द आ रहा है';

  @override
  String get navHome => 'होम';

  @override
  String get navFarmers => 'किसान';

  @override
  String get navVisits => 'विज़िट';

  @override
  String get navOrders => 'ऑर्डर';

  @override
  String get navMe => 'मैं';

  @override
  String get myDayTitle => 'मेरा दिन';

  @override
  String myDayKm(String km) {
    return 'आज $km कि.मी.';
  }

  @override
  String get myDayEmpty => 'आज अभी तक ड्यूटी नहीं';

  @override
  String get myDayEmptyHelp =>
      'होम से ड्यूटी पर जाएँ; आपका ट्रैक और कि.मी. यहाँ दिखेंगे।';

  @override
  String myDaySession(String start, String end) {
    return 'ड्यूटी $start – $end';
  }

  @override
  String myDaySessionActive(String start) {
    return '$start से ड्यूटी पर';
  }

  @override
  String myDayPoints(int pending, int accepted) {
    return '$pending लंबित · $accepted स्वीकृत';
  }

  @override
  String get myDayGapsTitle => 'अंतराल और कारण';

  @override
  String get myDayGapsHelp => 'अंतराल के कारण अगले अपडेट के साथ आएँगे।';

  @override
  String get myDayEndReasonManual => 'आपने समाप्त किया';

  @override
  String get myDayEndReasonAutoTime => 'दिन के अंत में समाप्त';

  @override
  String get myDayEndReasonAutoIdle => 'निष्क्रियता के बाद समाप्त';

  @override
  String get myDayEndReasonForced => 'मैनेजर ने समाप्त किया';

  @override
  String get myDayEndReasonRejected => 'दर्ज नहीं हुई';

  @override
  String get syncEntityDutySession => 'ड्यूटी सत्र';

  @override
  String get syncEntityLocationBatch => 'लोकेशन पॉइंट';

  @override
  String get syncEntityPolicyAcceptance => 'नीति स्वीकृति';
}
