// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'core_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Marathi (`mr`).
class CoreLocalizationsMr extends CoreLocalizations {
  CoreLocalizationsMr([String locale = 'mr']) : super(locale);

  @override
  String get appNameAgent => 'मित्र';

  @override
  String get appNameFarmer => 'किसान';

  @override
  String get splashTagline => 'तुमच्या शेतासाठी विश्वासू सल्ला';

  @override
  String get actionContinue => 'पुढे जा';

  @override
  String get actionBack => 'मागे';

  @override
  String get actionNext => 'पुढील';

  @override
  String get actionRetry => 'पुन्हा प्रयत्न करा';

  @override
  String get actionCancel => 'रद्द करा';

  @override
  String get actionDone => 'झाले';

  @override
  String get actionSkip => 'वगळा';

  @override
  String get actionClose => 'बंद करा';

  @override
  String get loading => 'लोड होत आहे';

  @override
  String get languagePickerTitle => 'तुमची भाषा निवडा';

  @override
  String get languagePickerSubtitle => 'ऐकण्यासाठी स्पीकर दाबा';

  @override
  String get languagePlayAudio => 'ऐका';

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
  String get languageEnglishName => 'इंग्रजी';

  @override
  String get languageTeluguName => 'तेलुगू';

  @override
  String get languageKannadaName => 'कन्नड';

  @override
  String get languageHindiName => 'हिंदी';

  @override
  String get languageMarathiName => 'मराठी';

  @override
  String get phoneLoginTitle => 'तुमचा मोबाईल नंबर टाका';

  @override
  String get phoneLabel => 'मोबाईल नंबर';

  @override
  String get phonePrefix => '+91';

  @override
  String get phoneHelper => 'आम्ही SMS ने 6 अंकी OTP पाठवू';

  @override
  String get phoneInvalid => 'योग्य 10 अंकी मोबाईल नंबर टाका';

  @override
  String get phoneSendOtp => 'OTP पाठवा';

  @override
  String get otpTitle => 'OTP टाका';

  @override
  String otpSubtitle(String phone) {
    return '+91 $phone वर पाठवला';
  }

  @override
  String get otpLabel => '6 अंकी OTP';

  @override
  String get otpResend => 'OTP पुन्हा पाठवा';

  @override
  String otpResendIn(int seconds) {
    return '$seconds सेकंदांत पुन्हा पाठवा';
  }

  @override
  String get otpInvalid => 'OTP चुकीचा आहे. पुन्हा प्रयत्न करा.';

  @override
  String get otpVerify => 'तपासा';

  @override
  String otpDigitLabel(int index) {
    return '6 पैकी $indexवा अंक';
  }

  @override
  String otpAttemptsLeft(int count) {
    return '$count प्रयत्न शिल्लक';
  }

  @override
  String otpLocked(int minutes) {
    return 'खूप वेळा चुकीचा OTP. $minutes मिनिटांनी पुन्हा प्रयत्न करा.';
  }

  @override
  String otpRateLimited(int minutes) {
    return 'खूप वेळा OTP मागितला. $minutes मिनिटांनी पुन्हा प्रयत्न करा.';
  }

  @override
  String get otpExpired => 'हा OTP संपला आहे. नवीन मागा.';

  @override
  String get phoneNotFound =>
      'हा नंबर नोंदणीकृत नाही. तुम्हाला जोडण्यासाठी मॅनेजरला सांगा.';

  @override
  String get networkError =>
      'कनेक्शन नाही. नेटवर्क तपासा आणि पुन्हा प्रयत्न करा.';

  @override
  String get consentTitle => 'तुमचे लोकेशन आणि डेटा';

  @override
  String get consentPoint1 => 'आम्ही तुमचे लोकेशन आणि भेटीचे फोटो घेतो.';

  @override
  String get consentPoint2 => 'लोकेशन फक्त ड्युटीवर असताना घेतले जाते.';

  @override
  String get consentPoint3 =>
      'याचा वापर प्रवास भत्ता आणि भेट क्रेडिटसाठी होतो.';

  @override
  String get consentPoint4 =>
      'तुमचे मॅनेजर आणि मालक ते पाहू शकतात. शेतकरी नाही.';

  @override
  String get consentAgree => 'मी सहमत आहे';

  @override
  String get consentPolicyLink => 'पूर्ण धोरण वाचा';

  @override
  String get consentDataCardTitle => 'पीक सल्ल्यासाठी माझा डेटा वापरा';

  @override
  String get consentDataCardBody =>
      'तुम्हाला मदत करण्यासाठी आम्ही तुमच्या पिकाचे फोटो आणि शेताची माहिती पाहतो.';

  @override
  String get consentRequired => 'आवश्यक';

  @override
  String get consentOffersCardTitle => 'मला ऑफर आणि टिप्स पाठवा';

  @override
  String get consentOffersCardBody => 'उत्पादने आणि शेतीच्या टिप्सबद्दल संदेश.';

  @override
  String get consentOptional => 'ऐच्छिक';

  @override
  String get consentReadAloud => 'वाचून ऐकवा';

  @override
  String get dutyOn => 'ड्युटीवर';

  @override
  String get dutyOff => 'ड्युटीवर नाही';

  @override
  String get dutyGoOn => 'ड्युटी सुरू करा';

  @override
  String get dutyGoOff => 'ड्युटी संपवा';

  @override
  String dutyElapsed(String duration) {
    return '$duration पासून ड्युटीवर';
  }

  @override
  String get dutyLocationNote => 'लोकेशन फक्त ड्युटीवर असताना चालू असते';

  @override
  String get syncSynced => 'सिंक झाले';

  @override
  String syncPending(int count) {
    return '$count बाकी';
  }

  @override
  String get syncFailed => 'सिंक अयशस्वी';

  @override
  String get offlineBanner =>
      'तुम्ही ऑफलाइन आहात. तुमचे काम सेव्ह आहे आणि नंतर सिंक होईल.';

  @override
  String get syncSyncing => 'सिंक होत आहे…';

  @override
  String get syncDetailsTitle => 'सिंक तपशील';

  @override
  String get syncNow => 'आता सिंक करा';

  @override
  String syncLastSync(String time) {
    return 'शेवटचे सिंक $time';
  }

  @override
  String get syncNeverSynced => 'अजून सिंक झाले नाही';

  @override
  String get syncAllDone => 'सर्व काही सिंक झाले';

  @override
  String get syncAllDoneHelp =>
      'ऑफलाइन जतन केलेले नवीन शेतकरी, शेते आणि फोटो सर्व्हरवर पोहोचेपर्यंत येथे दिसतील.';

  @override
  String syncPendingSection(int count) {
    return 'सिंकची वाट पाहत आहेत ($count)';
  }

  @override
  String syncFailedSection(int count) {
    return 'लक्ष देणे आवश्यक ($count)';
  }

  @override
  String get syncWaitingForPhoto => 'फोटो अपलोडची वाट पाहत आहे';

  @override
  String syncPhotoUploads(int count) {
    return 'अपलोड होत असलेले फोटो: $count';
  }

  @override
  String get syncTransportError =>
      'सर्व्हरशी संपर्क होऊ शकला नाही. ते आपोआप पुन्हा प्रयत्न करेल.';

  @override
  String syncNextAttempt(String time) {
    return 'पुढील प्रयत्न $time';
  }

  @override
  String syncItemTitle(String action, String entity) {
    return '$action $entity';
  }

  @override
  String get syncActionCreate => 'नवीन';

  @override
  String get syncActionUpdate => 'संपादित';

  @override
  String get syncActionDelete => 'हटवलेले';

  @override
  String get syncEntityFarmer => 'शेतकरी';

  @override
  String get syncEntityFarm => 'शेत';

  @override
  String get syncEntityCropPlot => 'पीक प्लॉट';

  @override
  String get syncEntityConsent => 'संमती';

  @override
  String get syncEntityOther => 'आयटम';

  @override
  String syncSavedAt(String time) {
    return 'जतन केले $time';
  }

  @override
  String get syncRejectedDefault =>
      'सर्व्हरने हा आयटम स्वीकारला नाही. तो संपादित करून पुन्हा प्रयत्न करा.';

  @override
  String get syncRetryAll => 'सर्व पुन्हा प्रयत्न करा';

  @override
  String get syncDiscard => 'टाकून द्या';

  @override
  String get visitVerified => 'पडताळलेली';

  @override
  String get visitPartial => 'अंशतः';

  @override
  String get visitUnverified => 'न पडताळलेली';

  @override
  String visitScore(int score) {
    return '100 पैकी $score गुण';
  }

  @override
  String visitDurationMinutes(int minutes) {
    return '$minutes मिनिटे';
  }

  @override
  String get visitPurposeAdvisory => 'सल्ला';

  @override
  String get visitPurposeScouting => 'शेत पाहणी';

  @override
  String get visitPurposeDemo => 'डेमो';

  @override
  String get visitPurposeCollection => 'वसुली';

  @override
  String get visitPurposeSale => 'विक्री';

  @override
  String get visitPurposeMeeting => 'बैठक';

  @override
  String get proofGeofence => 'शेताच्या हद्दीत';

  @override
  String get proofGeofenceMissing => 'तुम्ही शेताच्या हद्दीबाहेर होता';

  @override
  String get proofPhoto => 'फोटो घेतला';

  @override
  String get proofPhotoMissing => 'भेटीदरम्यान फोटो घेतला नाही';

  @override
  String get proofFarmerConfirmed => 'शेतकऱ्याने पुष्टी केली';

  @override
  String get proofFarmerConfirmedMissing =>
      'शेतकऱ्याने भेटीची पुष्टी केली नाही';

  @override
  String get proofDuration => 'शेतावर किमान वेळ पूर्ण';

  @override
  String get proofDurationMissing => 'भेट 10 मिनिटांपेक्षा कमी होती';

  @override
  String get proofDone => 'झाले';

  @override
  String get proofMissing => 'नाही';

  @override
  String get cameraHoldSteady => 'स्थिर धरा';

  @override
  String get cameraGoodLight => 'चांगला प्रकाश';

  @override
  String get cameraFillFrame => 'फ्रेम भरा';

  @override
  String get cameraLeafFrame => 'पान फ्रेमच्या आत ठेवा';

  @override
  String get photoReviewHeading => 'तुमचा फोटो तपासा';

  @override
  String photoReviewTitle(int index, int total) {
    return 'फोटो $index / $total';
  }

  @override
  String get photoQualityOk => 'चांगला फोटो';

  @override
  String get photoQualityBlurry => 'अस्पष्ट आहे';

  @override
  String get photoQualityDark => 'खूप अंधार आहे';

  @override
  String get photoQualityChecking => 'फोटो तपासत आहोत';

  @override
  String get photoTipBlurry =>
      'फोन स्थिर धरा, पानावर टॅप करून फोकस करा आणि पुन्हा काढा';

  @override
  String get photoTipDark =>
      'चांगल्या उजेडात जा, सावलीतून बाहेर या आणि पुन्हा काढा';

  @override
  String get photoTipOk => 'फोटो चांगला आहे';

  @override
  String get photoRetake => 'पुन्हा काढा';

  @override
  String get photoUse => 'हा फोटो वापरा';

  @override
  String photoSizeKb(int kb) {
    return '$kb KB';
  }

  @override
  String photoDimensions(int width, int height) {
    return '$width × $height px';
  }

  @override
  String get confidenceHigh => 'उच्च विश्वास';

  @override
  String get confidenceMedium => 'मध्यम विश्वास';

  @override
  String get confidenceLow => 'तात्पुरते';

  @override
  String get diagnosisSymptomsTitle => 'ही लक्षणे तपासा';

  @override
  String get diagnosisProvisionalNote => 'आमचे तज्ज्ञ 24 तासांत पुष्टी करतील';

  @override
  String get diagnosisProblem => 'समस्या';

  @override
  String get treatmentOrganic => 'सेंद्रिय';

  @override
  String get treatmentChemical => 'रासायनिक';

  @override
  String get treatmentActiveIngredient => 'सक्रिय घटक';

  @override
  String get treatmentDosePerAcre => 'प्रति एकर';

  @override
  String get treatmentDosePerTank => 'प्रति 15 ली टाकी';

  @override
  String treatmentSafetyInterval(int days) {
    return 'काढणीपूर्वी $days दिवस थांबा';
  }

  @override
  String get treatmentPpeGloves => 'हातमोजे';

  @override
  String get treatmentPpeMask => 'मास्क';

  @override
  String get treatmentPpeGoggles => 'चष्मा';

  @override
  String get treatmentPpeTitle => 'घाला';

  @override
  String get ownBrand => 'स्वतःचा ब्रँड';

  @override
  String get productAdd => 'जोडा';

  @override
  String get productAdded => 'जोडले';

  @override
  String productStockAtStore(int count, String store) {
    return '$store येथे $count स्टॉकमध्ये';
  }

  @override
  String get productOutOfStock => 'स्टॉक नाही';

  @override
  String get productPack => 'पॅक';

  @override
  String cartItems(int count) {
    return '$count वस्तू';
  }

  @override
  String get cartTotal => 'एकूण';

  @override
  String get cartCheckout => 'पैसे भरा';

  @override
  String get paymentMethodTitle => 'तुम्ही कसे पैसे भराल?';

  @override
  String get paymentUpiQr => 'UPI QR';

  @override
  String get paymentUpiQrHint => 'स्कॅन करून आता पैसे भरा';

  @override
  String get paymentLink => 'पेमेंट लिंक';

  @override
  String get paymentLinkHint => 'SMS किंवा WhatsApp ने पाठवा';

  @override
  String get paymentCash => 'रोख';

  @override
  String get paymentCashHint => 'रोख घ्या आणि पावती द्या';

  @override
  String get paymentCredit => 'उधारी';

  @override
  String get paymentCreditHint => 'शेतकऱ्याच्या खात्यात जोडा';

  @override
  String get upiWaiting => 'पेमेंटची वाट पाहत आहोत';

  @override
  String get upiPaid => 'पेमेंट मिळाले';

  @override
  String get upiFailed => 'पेमेंट अयशस्वी';

  @override
  String upiExpiresIn(String time) {
    return '$time मध्ये संपेल';
  }

  @override
  String get upiAmount => 'रक्कम';

  @override
  String get upiScanHint => 'शेतकऱ्याला कोणत्याही UPI ॲपने स्कॅन करायला सांगा';

  @override
  String get upiRetry => 'नवीन QR दाखवा';

  @override
  String get khataBalance => 'थकबाकी';

  @override
  String khataDueDate(String date) {
    return '$date पर्यंत देय';
  }

  @override
  String get khataDebit => 'दिले';

  @override
  String get khataCredit => 'मिळाले';

  @override
  String get khataNoEntries => 'अजून नोंदी नाहीत';

  @override
  String get khataPayNow => 'आता पैसे भरा';

  @override
  String get khataCollect => 'वसूल करा';

  @override
  String get emptyDefaultTitle => 'अजून येथे काही नाही';

  @override
  String get emptyDefaultHelp => 'जोडल्यानंतर वस्तू येथे दिसतील.';

  @override
  String get errorTitle => 'काहीतरी चूक झाली';

  @override
  String get errorHelp => 'कनेक्शन तपासा आणि पुन्हा प्रयत्न करा.';

  @override
  String get ratingTitle => 'तुमच्या भेटीला रेटिंग द्या';

  @override
  String get rating1 => 'खूप वाईट';

  @override
  String get rating2 => 'वाईट';

  @override
  String get rating3 => 'ठीक';

  @override
  String get rating4 => 'चांगले';

  @override
  String get rating5 => 'खूप चांगले';

  @override
  String stepperStepOf(int current, int total) {
    return '$total पैकी पायरी $current';
  }

  @override
  String farmerLastVisit(String date) {
    return 'शेवटची भेट $date';
  }

  @override
  String get farmerNoVisit => 'अजून भेट नाही';

  @override
  String farmerBalanceDue(String amount) {
    return 'थकबाकी $amount';
  }

  @override
  String get farmerVillage => 'गाव';

  @override
  String get statTrendUp => 'वाढ';

  @override
  String get statTrendDown => 'घट';

  @override
  String get statTrendFlat => 'बदल नाही';

  @override
  String get stageSowing => 'पेरणी';

  @override
  String get stageVegetative => 'वाढ';

  @override
  String get stageFlowering => 'फुलोरा';

  @override
  String get stageFruiting => 'फळधारणा';

  @override
  String get stageHarvest => 'काढणी';

  @override
  String get settingsTheme => 'थीम';

  @override
  String get themeLight => 'लाइट';

  @override
  String get themeSunlight => 'ऊन';

  @override
  String get settingsTitle => 'सेटिंग्ज';

  @override
  String get settingsLanguage => 'भाषा';

  @override
  String get skeletonLoading => 'मजकूर लोड होत आहे';

  @override
  String get farmersTitle => 'शेतकरी';

  @override
  String get farmersSearchHint => 'नाव, फोन किंवा गाव शोधा';

  @override
  String get farmersAddFarmer => 'शेतकरी जोडा';

  @override
  String get farmersEmptyTitle => 'अजून शेतकरी नाहीत';

  @override
  String get farmersEmptyHelp =>
      'भेटी आणि ऑर्डर सुरू करण्यासाठी पहिला शेतकरी जोडा.';

  @override
  String get farmersNoResults => 'तुमच्या शोधाशी जुळणारे शेतकरी नाहीत';

  @override
  String get farmersFilterVillage => 'गाव';

  @override
  String get farmersFilterCrop => 'पीक';

  @override
  String get farmersFilterAll => 'सर्व';

  @override
  String farmersCount(int count) {
    return '$count शेतकरी';
  }

  @override
  String get farmerPendingSync => 'ऑनलाइन झाल्यावर सिंक होईल';

  @override
  String get farmerPhoneUnverified => 'फोन पडताळलेला नाही';

  @override
  String get farmerRejected => 'लक्ष द्या';

  @override
  String get regTitle => 'शेतकरी जोडा';

  @override
  String get regStepBasics => 'शेतकऱ्याचा तपशील';

  @override
  String get regStepBoundary => 'शेताची हद्द';

  @override
  String get regStepCrops => 'पिके';

  @override
  String get regStepConsent => 'संमती';

  @override
  String get regStepReview => 'तपासा आणि जतन करा';

  @override
  String get regResumeDraft => 'जिथे थांबला होता तिथून पुढे';

  @override
  String get regDiscardDraft => 'मसुदा काढून टाका';

  @override
  String get regFixIssues => 'पुढे जाण्यासाठी अधोरेखित फील्ड दुरुस्त करा';

  @override
  String get regNameLabel => 'शेतकऱ्याचे नाव';

  @override
  String get regNameHint => 'ओळखपत्रावर आहे तसे';

  @override
  String get regPhoneLabel => 'शेतकऱ्याचा मोबाइल नंबर';

  @override
  String get regPhoneHelper => 'शेतकऱ्याला OTP पाठवला जाईल';

  @override
  String get regSendOtpToFarmer => 'शेतकऱ्याला OTP पाठवा';

  @override
  String get regOtpSent => 'शेतकऱ्याला OTP पाठवला. त्यांना कोड विचारा.';

  @override
  String get regPhoneVerified => 'फोन पडताळला';

  @override
  String get regVerifyLater => 'नंतर पडताळा';

  @override
  String get regVerifyLaterNote =>
      'सिग्नल नाही? आता जतन करा आणि शेतकरी प्रोफाइलमधून फोन पडताळा.';

  @override
  String get regVerifyLaterChosen => 'नंतर पडताळला जाईल';

  @override
  String get regDuplicatePhone => 'या नंबरचा शेतकरी आधीच आहे';

  @override
  String get regDuplicateOpen => 'असलेला शेतकरी उघडा';

  @override
  String get regVillageLabel => 'गाव';

  @override
  String get regVillageHint => 'गाव निवडा';

  @override
  String get regVillageTyped => 'गावाचे नाव';

  @override
  String get regVillageNoneSynced =>
      'पहिल्या सिंकनंतर गावे लोड होतील. सध्या गावाचे नाव टाइप करा.';

  @override
  String get regLandmarkLabel => 'खूण';

  @override
  String get regLandmarkHint => 'मंदिर, शाळेजवळ…';

  @override
  String get regLanguageLabel => 'शेतकऱ्याची भाषा';

  @override
  String get regOwnershipLabel => 'जमीन';

  @override
  String get regBoundaryWalk => 'भोवती चाला';

  @override
  String get regBoundaryTap => 'कोपरे टॅप करा';

  @override
  String get regStartWalk => 'चालायला सुरुवात करा';

  @override
  String get regStopWalk => 'थांबवा';

  @override
  String get regClosePolygon => 'हद्द बंद करा';

  @override
  String get regUndoPoint => 'बिंदू मागे घ्या';

  @override
  String get regClearBoundary => 'पुसा';

  @override
  String regPointsCount(int count) {
    return '$count बिंदू';
  }

  @override
  String regAccuracy(int metres) {
    return 'GPS अचूकता ±$metres मी';
  }

  @override
  String get regAccuracyWaiting => 'GPS ची वाट पाहत आहे…';

  @override
  String get regLocationOff => 'हद्दीवर चालण्यासाठी लोकेशन सुरू करा';

  @override
  String get regLocationDenied => 'हद्दीवर चालण्यासाठी लोकेशन परवानगी हवी';

  @override
  String get regTapHint => 'नकाशावर शेताचे चारही कोपरे टॅप करा';

  @override
  String get regWalkHint => 'शेताच्या कडेने चाला. चालताना बिंदू जोडले जातील.';

  @override
  String regComputedArea(String acres) {
    return 'मोजलेले क्षेत्र $acres एकर';
  }

  @override
  String get regAreaLabel => 'क्षेत्र एकरात';

  @override
  String get regAreaHint => 'शेतकरी सांगतो तसे';

  @override
  String get regUseMeasured => 'मोजलेले वापरा';

  @override
  String get regAreaWarning =>
      'नोंदवलेले क्षेत्र मोजलेल्या क्षेत्रापेक्षा 30% हून जास्त वेगळे आहे. जतन करण्यापूर्वी तपासा.';

  @override
  String get regBoundaryInvalid =>
      'हद्द स्वतःला छेदते आहे. शेवटचे बिंदू मागे घेऊन पुन्हा प्रयत्न करा.';

  @override
  String get regFarmNameLabel => 'शेताचे नाव (ऐच्छिक)';

  @override
  String get regFarmNameHint => 'घरचे शेत';

  @override
  String get regSoilLabel => 'मातीचा प्रकार';

  @override
  String get regIrrigationLabel => 'सिंचन';

  @override
  String get regFarmPhoto => 'शेताचा फोटो (ऐच्छिक)';

  @override
  String get regTakePhoto => 'फोटो काढा';

  @override
  String get regPhotoAdded => 'फोटो जोडला';

  @override
  String get regPhotoRemove => 'काढा';

  @override
  String regFarmPhotosCount(int count) {
    return '$count फोटो';
  }

  @override
  String get regCropsHelp => 'या हंगामात या शेतात असलेले प्रत्येक पीक जोडा.';

  @override
  String get regAddCrop => 'पीक जोडा';

  @override
  String get regCropLabel => 'पीक';

  @override
  String get regVarietyLabel => 'वाण';

  @override
  String get regVarietyHint => 'उदा. MTU-1010';

  @override
  String get regSowingDateLabel => 'पेरणीची तारीख';

  @override
  String get regSowingDateHint => 'DD-MM-YYYY';

  @override
  String regSeasonAuto(String season) {
    return 'हंगाम: $season';
  }

  @override
  String get regPlotAreaLabel => 'क्षेत्र (एकर, ऐच्छिक)';

  @override
  String get regRemoveCrop => 'पीक काढा';

  @override
  String regPlotTitle(int index) {
    return 'पीक $index';
  }

  @override
  String get regAddFarm => 'आणखी एक शेत जोडा';

  @override
  String regFarmsCount(int count) {
    return '$count शेते';
  }

  @override
  String regFarmIndex(int index) {
    return 'शेत $index';
  }

  @override
  String get regConsentIntro => 'हे शेतकऱ्याला त्यांच्या भाषेत वाचून दाखवा.';

  @override
  String get regConsentNotice =>
      'पीक सल्ला देण्यासाठी आणि भेटींच्या नोंदी ठेवण्यासाठी आम्ही तुमचे नाव, फोन, गाव आणि शेताचा तपशील ठेवू. तुम्ही केव्हाही आम्हाला थांबवायला सांगू शकता.';

  @override
  String get regConsentMarketingNotice =>
      'तुमच्या परवानगीने आम्ही SMS किंवा WhatsApp वर ऑफर आणि शेतीच्या टिप्सही पाठवू.';

  @override
  String get regConsentGiven => 'शेतकरी सहमत आहे';

  @override
  String get regReviewFarmer => 'शेतकरी';

  @override
  String get regReviewFarms => 'शेते आणि पिके';

  @override
  String get regReviewConsent => 'संमती';

  @override
  String get regReviewSyncNote =>
      'आता या फोनवर जतन झाले; नेटवर्क आल्यावर सर्व्हरला पाठवले जाईल.';

  @override
  String get regSave => 'शेतकरी जतन करा';

  @override
  String get regSaveFarm => 'शेत जतन करा';

  @override
  String get regEdit => 'संपादित करा';

  @override
  String get regSaved => 'शेतकरी जतन झाला';

  @override
  String get regIssueName => 'शेतकऱ्याचे नाव नोंदवा';

  @override
  String get regIssuePhoneUnverified => 'फोन पडताळा किंवा नंतर पडताळा निवडा';

  @override
  String get regIssueVillage => 'गाव निवडा';

  @override
  String get regIssueLanguage => 'शेतकऱ्याची भाषा निवडा';

  @override
  String get regIssueBoundary => 'हद्दीचे किमान 3 बिंदू चिन्हांकित करा';

  @override
  String get regIssueArea => 'क्षेत्र एकरात नोंदवा';

  @override
  String get regIssueCrop => 'किमान एक पीक जोडा';

  @override
  String get regIssueSowingDate => 'प्रत्येक पिकाची पेरणीची तारीख नोंदवा';

  @override
  String get regIssueConsent => 'नोंदणीसाठी डेटा संमती आवश्यक आहे';

  @override
  String get soilBlack => 'काळी माती';

  @override
  String get soilRed => 'तांबडी माती';

  @override
  String get soilSandy => 'वाळूमिश्रित माती';

  @override
  String get soilLoamy => 'पोयटा माती';

  @override
  String get soilClay => 'चिकण माती';

  @override
  String get soilAlluvial => 'गाळाची माती';

  @override
  String get soilLaterite => 'जांभा माती';

  @override
  String get irrigationRainfed => 'पावसावर आधारित';

  @override
  String get irrigationBorewell => 'बोअरवेल';

  @override
  String get irrigationCanal => 'कालवा';

  @override
  String get irrigationTank => 'तलाव';

  @override
  String get irrigationOpenWell => 'उघडी विहीर';

  @override
  String get irrigationDrip => 'ठिबक';

  @override
  String get irrigationSprinkler => 'तुषार';

  @override
  String get ownershipOwn => 'स्वतःची';

  @override
  String get ownershipLeased => 'भाडेपट्ट्याने';

  @override
  String get seasonKharif => 'खरीप';

  @override
  String get seasonRabi => 'रब्बी';

  @override
  String get seasonZaid => 'झायद (उन्हाळी)';

  @override
  String get profileTabOverview => 'आढावा';

  @override
  String get profileTabVisits => 'भेटी';

  @override
  String get profileTabDiagnoses => 'निदान';

  @override
  String get profileTabOrders => 'ऑर्डर';

  @override
  String get profileTabKhata => 'खाते';

  @override
  String get profileStartVisit => 'भेट सुरू करा';

  @override
  String get profileScout => 'पीक पाहणी';

  @override
  String get profileNewOrder => 'नवीन ऑर्डर';

  @override
  String get profileCollect => 'वसुली';

  @override
  String get profileComingSoon => 'पुढील अपडेटमध्ये येईल';

  @override
  String get profileVisitsEmpty => 'अजून भेटी नाहीत';

  @override
  String get profileDiagnosesEmpty => 'अजून निदान नाहीत';

  @override
  String get profileOrdersEmpty => 'अजून ऑर्डर नाहीत';

  @override
  String get profileKhataEmpty => 'अजून खात्यात नोंदी नाहीत';

  @override
  String get profilePhone => 'फोन';

  @override
  String get profileLandmark => 'खूण';

  @override
  String get profileLanguage => 'भाषा';

  @override
  String get profileOwnership => 'जमीन';

  @override
  String get profileFarms => 'शेते';

  @override
  String profileAcres(String acres) {
    return '$acres एकर';
  }

  @override
  String get profileAddFarm => 'शेत जोडा';

  @override
  String get profileEditFarm => 'शेत संपादित करा';

  @override
  String profileFarmPlots(int count) {
    return '$count पिके';
  }

  @override
  String get profileNoFarms => 'अजून शेते नाहीत';

  @override
  String get profileDuplicateTitle => 'दुबार — एकत्र करायचे?';

  @override
  String get profileDuplicateBody =>
      'सर्व्हरवर या नंबरचा शेतकरी आधीच आहे. असलेली नोंद उघडून तपशील एकत्र करा.';

  @override
  String get profileRejectedTitle => 'सिंक नाकारले';

  @override
  String get profileRejectedHelp =>
      'दुरुस्त करून पुन्हा प्रयत्न करण्यासाठी सिंक तपशील उघडा.';

  @override
  String get profileNotFound => 'शेतकरी सापडला नाही';

  @override
  String get profileVerifyPhone => 'फोन पडताळा';

  @override
  String get consentGiven => 'दिली';

  @override
  String get consentNotGiven => 'दिली नाही';

  @override
  String get farmEditTitle => 'शेत संपादित करा';

  @override
  String get farmAddTitle => 'शेत जोडा';

  @override
  String get mapNoBoundary => 'अजून हद्द नाही';

  @override
  String get mapAttribution => '© OpenStreetMap योगदानकर्ते';

  @override
  String get mapCurrentPosition => 'तुमचे स्थान';

  @override
  String mapCorner(int index) {
    return 'कोपरा $index';
  }

  @override
  String get mapFarmBoundary => 'शेताची हद्द';
}
