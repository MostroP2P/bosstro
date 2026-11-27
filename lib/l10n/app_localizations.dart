import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_it.dart';
import 'app_localizations_nl.dart';
import 'app_localizations_pt.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('de'),
    Locale('es'),
    Locale('fr'),
    Locale('it'),
    Locale('nl'),
    Locale('pt'),
  ];

  /// The app's name. A brand: keep it unchanged in every locale
  ///
  /// In en, this message translates to:
  /// **'Bosstro'**
  String get appName;

  /// Bottom bar destination: the disputes of the active node, waiting, in progress and closed
  ///
  /// In en, this message translates to:
  /// **'Disputes'**
  String get navDisputes;

  /// Bottom bar destination: settings
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// Tab app bar status line, before the solver chooses a Mostro node
  ///
  /// In en, this message translates to:
  /// **'No node selected'**
  String get noNodeSelected;

  /// Header of the Disputes tab
  ///
  /// In en, this message translates to:
  /// **'Disputes'**
  String get disputesTitle;

  /// Empty state title of Disputes, Pending
  ///
  /// In en, this message translates to:
  /// **'No disputes waiting'**
  String get pendingEmptyTitle;

  /// Empty state explanation of Disputes, Pending
  ///
  /// In en, this message translates to:
  /// **'No dispute on this node is waiting for a solver. When a trade opens one, it shows up here for you to take.'**
  String get pendingEmptyBody;

  /// Empty state title of Disputes, In progress
  ///
  /// In en, this message translates to:
  /// **'No disputes in progress'**
  String get inProgressEmptyTitle;

  /// Empty state explanation of Disputes, In progress
  ///
  /// In en, this message translates to:
  /// **'Disputes you take show up here. If a take got no answer, recover it.'**
  String get inProgressEmptyBody;

  /// Header of the Settings tab
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// Settings group header: how the app itself looks and reads (its language)
  ///
  /// In en, this message translates to:
  /// **'App'**
  String get settingsGroupApp;

  /// Settings row label: the app's language; its value is the language in use, or languageSystem
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// Title of the sheet that lists the app's languages
  ///
  /// In en, this message translates to:
  /// **'Choose a language'**
  String get languageSheetTitle;

  /// The default choice: the app follows the language of the phone or computer
  ///
  /// In en, this message translates to:
  /// **'System language'**
  String get languageSystem;

  /// Under languageSystem: the language that choice gives the app now
  ///
  /// In en, this message translates to:
  /// **'Same as your device: {language}'**
  String languageSystemDetail(String language);

  /// The About screen: its title, and the Settings row that opens it
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get aboutScreenTitle;

  /// Under the app's name on About
  ///
  /// In en, this message translates to:
  /// **'The app for Mostro dispute solvers'**
  String get aboutTagline;

  /// About row label: the app's licence; its value is aboutLicenseName
  ///
  /// In en, this message translates to:
  /// **'License'**
  String get aboutLicenseLabel;

  /// The licence's short name, the same in every language
  ///
  /// In en, this message translates to:
  /// **'AGPLv3+'**
  String get aboutLicenseName;

  /// Title of the dialog with the licence notice, which stays in English (a translated licence has no legal force)
  ///
  /// In en, this message translates to:
  /// **'GNU Affero General Public License v3'**
  String get aboutLicenseDialogTitle;

  /// About row label: opens the app's repository in the browser
  ///
  /// In en, this message translates to:
  /// **'Source code'**
  String get aboutSourceCodeLabel;

  /// Group header for the app's own rows: on the About screen (license, source code) and as the first group of the node technical data screen and of its copied text (version, commit)
  ///
  /// In en, this message translates to:
  /// **'Application'**
  String get aboutAppSection;

  /// About screen — Version row label
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get aboutVersionLabel;

  /// About screen — Commit Hash row label
  ///
  /// In en, this message translates to:
  /// **'Commit Hash'**
  String get aboutCommitHashLabel;

  /// Generic copy action button label (e.g. in SnackBar actions)
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copyButtonLabel;

  /// Snackbar shown after copying a link to clipboard
  ///
  /// In en, this message translates to:
  /// **'Link copied to clipboard'**
  String get linkCopiedToClipboard;

  /// Snackbar confirming a value was copied to the clipboard
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get copied;

  /// Snackbar after copying a chat message that carries a party's chat key (a secret): copied as sensitive and cleared after a minute
  ///
  /// In en, this message translates to:
  /// **'Chat key copied. It is cleared from the clipboard in 60 seconds.'**
  String get chatKeyCopied;

  /// Screen reader hint of the long press on a chat message, which copies it
  ///
  /// In en, this message translates to:
  /// **'Copy the message'**
  String get chatCopyHint;

  /// Data row label of an id (a dispute's or an order's)
  ///
  /// In en, this message translates to:
  /// **'ID'**
  String get idLabel;

  /// Screen reader hint of a row that copies an id
  ///
  /// In en, this message translates to:
  /// **'Copy ID'**
  String get copyIdHint;

  /// Easter egg shown when the mascot is tapped on 31 October, the whitepaper's anniversary — and Halloween
  ///
  /// In en, this message translates to:
  /// **'31 October 2008: nine pages, nobody\'s permission. Happy Halloween.'**
  String get easterEggWhitepaper;

  /// Easter egg shown when the mascot is tapped on 3 January: the headline Satoshi embedded in the genesis block. A quotation — keep it in English, unchanged, in every locale
  ///
  /// In en, this message translates to:
  /// **'The Times 03/Jan/2009 Chancellor on brink of second bailout for banks'**
  String get easterEggGenesis;

  /// Easter egg shown when the mascot is tapped on 22 May, Bitcoin Pizza Day
  ///
  /// In en, this message translates to:
  /// **'22 May 2010: 10,000 BTC for two pizzas. Hope they were good.'**
  String get easterEggPizzaDay;

  /// Welcome screen headline
  ///
  /// In en, this message translates to:
  /// **'Resolve Mostro disputes'**
  String get welcomeTitle;

  /// Welcome screen: what the app is for
  ///
  /// In en, this message translates to:
  /// **'Take a node\'s disputes, talk with the buyer and the seller, and close them, from your phone.'**
  String get welcomeBody;

  /// Welcome primary action: log in with an existing solver secret key
  ///
  /// In en, this message translates to:
  /// **'Log in'**
  String get welcomeLogIn;

  /// Welcome secondary action: generate a new solver key
  ///
  /// In en, this message translates to:
  /// **'Create new account'**
  String get welcomeCreateAccount;

  /// Welcome: shown when the stored solver key could not be read or loaded at startup. Nothing was deleted
  ///
  /// In en, this message translates to:
  /// **'The saved key could not be read on this phone. Log in again with your secret key. Logging in with another key replaces the saved one.'**
  String get welcomeKeyUnreadable;

  /// Warning on Log in and Create new account: the solver key must not be the trader identity's key
  ///
  /// In en, this message translates to:
  /// **'Never use the key you trade with. A solver key that is also a trading key links both roles publicly.'**
  String get traderKeyWarning;

  /// App bar title of the Log in screen
  ///
  /// In en, this message translates to:
  /// **'Log in'**
  String get loginTitle;

  /// Log in: heading above the secret key field
  ///
  /// In en, this message translates to:
  /// **'Your solver secret key'**
  String get loginHeading;

  /// Log in: what to enter
  ///
  /// In en, this message translates to:
  /// **'Paste or scan the secret key (nsec) whose npub your node operator registered as a solver.'**
  String get loginBody;

  /// Log in: what to enter, where there is no QR scanner (Linux, web)
  ///
  /// In en, this message translates to:
  /// **'Paste the secret key (nsec) whose npub your node operator registered as a solver.'**
  String get loginBodyPaste;

  /// Placeholder of the secret key field; the nsec prefix, keep as is
  ///
  /// In en, this message translates to:
  /// **'nsec1…'**
  String get secretKeyHint;

  /// Tooltip: reveal the secret key typed in the field
  ///
  /// In en, this message translates to:
  /// **'Show key'**
  String get showSecretKey;

  /// Tooltip: hide the secret key typed in the field
  ///
  /// In en, this message translates to:
  /// **'Hide key'**
  String get hideSecretKey;

  /// Action under a field: paste from the clipboard
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get pasteAction;

  /// Action under a field: scan a QR code with the camera
  ///
  /// In en, this message translates to:
  /// **'Scan QR'**
  String get scanQrAction;

  /// Error under the field when Paste finds nothing
  ///
  /// In en, this message translates to:
  /// **'The clipboard is empty.'**
  String get clipboardEmpty;

  /// Log in: check the entered key and show its npub
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get loginContinue;

  /// Log in error: nothing entered
  ///
  /// In en, this message translates to:
  /// **'Enter your secret key.'**
  String get keyErrorEmpty;

  /// Log in error: an npub was entered instead of an nsec
  ///
  /// In en, this message translates to:
  /// **'That is a public key (npub). Logging in needs the secret key (nsec).'**
  String get keyErrorPublicKey;

  /// Log in error: not an nsec nor a hex secret key
  ///
  /// In en, this message translates to:
  /// **'This is not a valid secret key. Enter an nsec1… key or its 64-character hex form.'**
  String get keyErrorInvalid;

  /// Log in confirmation step: question above the npub the entered key stands for
  ///
  /// In en, this message translates to:
  /// **'Is this the npub registered as a solver?'**
  String get loginConfirmHeading;

  /// Log in confirmation step: why to compare the npub
  ///
  /// In en, this message translates to:
  /// **'Compare it with the npub your node operator added. If it is not the same, this key cannot resolve disputes on that node.'**
  String get loginConfirmBody;

  /// Log in confirmation: confirm the npub and log in. Repeats the opener's verb
  ///
  /// In en, this message translates to:
  /// **'Yes, log in'**
  String get loginConfirmAnswer;

  /// Log in confirmation: go back and enter another key
  ///
  /// In en, this message translates to:
  /// **'No, use another key'**
  String get loginConfirmBack;

  /// Error when loading or storing the solver key failed
  ///
  /// In en, this message translates to:
  /// **'The key could not be saved on this phone. Try again.'**
  String get keySaveFailed;

  /// Label of a public key in npub form; keep as is
  ///
  /// In en, this message translates to:
  /// **'npub'**
  String get npubLabel;

  /// Label of the secret key card
  ///
  /// In en, this message translates to:
  /// **'Secret key (nsec)'**
  String get secretKeyLabel;

  /// Action / screen reader label: copy the npub
  ///
  /// In en, this message translates to:
  /// **'Copy npub'**
  String get copyNpub;

  /// Action / screen reader label: copy the secret key
  ///
  /// In en, this message translates to:
  /// **'Copy secret key'**
  String get copySecretKey;

  /// Action: share the npub through the system share sheet
  ///
  /// In en, this message translates to:
  /// **'Share npub'**
  String get shareNpub;

  /// Screen reader label of the npub QR code
  ///
  /// In en, this message translates to:
  /// **'QR code of your npub'**
  String get npubQrLabel;

  /// App bar title of the QR scanner
  ///
  /// In en, this message translates to:
  /// **'Scan QR'**
  String get scanTitle;

  /// QR scanner: instruction over the camera preview
  ///
  /// In en, this message translates to:
  /// **'Point the camera at the QR code of your secret key.'**
  String get scanHint;

  /// QR scanner: the camera could not start (no camera or permission refused)
  ///
  /// In en, this message translates to:
  /// **'The camera is not available. Go back and paste the key instead.'**
  String get scanUnavailable;

  /// App bar title of Create new account
  ///
  /// In en, this message translates to:
  /// **'Create new account'**
  String get createTitle;

  /// Create new account, step 1: heading
  ///
  /// In en, this message translates to:
  /// **'Your new secret key'**
  String get createKeyHeading;

  /// Create new account, step 1: why the secret key must be saved
  ///
  /// In en, this message translates to:
  /// **'It is the only way to log in to this account. Write it down somewhere safe and private: anyone who has it can resolve disputes as you.'**
  String get createKeyBody;

  /// Create new account, step 1: checkbox the solver ticks before continuing
  ///
  /// In en, this message translates to:
  /// **'I saved my secret key somewhere safe'**
  String get createBackupConfirm;

  /// Create new account, step 1: go on once the backup is confirmed
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get createContinue;

  /// Create new account, step 2: heading
  ///
  /// In en, this message translates to:
  /// **'Your npub'**
  String get createNpubHeading;

  /// Create new account, step 2: what to do with the npub
  ///
  /// In en, this message translates to:
  /// **'Send this npub to your node operator so they register you as a solver. Until then you can see the disputes but not take them.'**
  String get createNpubBody;

  /// Last button of Create new account: opens the node selector
  ///
  /// In en, this message translates to:
  /// **'Choose your node'**
  String get createDone;

  /// Settings group header: the solver's key
  ///
  /// In en, this message translates to:
  /// **'Solver key'**
  String get settingsGroupKey;

  /// Settings row: the solver's npub; opens it with its QR
  ///
  /// In en, this message translates to:
  /// **'Your npub'**
  String get settingsNpub;

  /// Settings row: show the secret key for backup
  ///
  /// In en, this message translates to:
  /// **'Back up secret key'**
  String get settingsBackup;

  /// Settings row: remove the key from this phone
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get settingsLogOut;

  /// Dialog before showing the secret key
  ///
  /// In en, this message translates to:
  /// **'Show your secret key?'**
  String get backupWarnTitle;

  /// Dialog before showing the secret key: the risk
  ///
  /// In en, this message translates to:
  /// **'Anyone who sees it can resolve disputes as you. Make sure nobody is looking at your screen.'**
  String get backupWarnBody;

  /// Dialog answer: show the secret key
  ///
  /// In en, this message translates to:
  /// **'Show secret key'**
  String get backupWarnAnswer;

  /// Dialog way out
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// App bar title of the backup screen
  ///
  /// In en, this message translates to:
  /// **'Secret key backup'**
  String get backupTitle;

  /// Backup screen: what the secret key is for
  ///
  /// In en, this message translates to:
  /// **'Keep it somewhere safe and private. It is the only way to log in to this account on another phone.'**
  String get backupBody;

  /// Backup screen: the stored key could not be read
  ///
  /// In en, this message translates to:
  /// **'The secret key could not be read on this phone.'**
  String get backupUnavailable;

  /// Log out confirmation title
  ///
  /// In en, this message translates to:
  /// **'Log out?'**
  String get logOutTitle;

  /// Log out confirmation: what happens
  ///
  /// In en, this message translates to:
  /// **'Your secret key will be removed from this phone. Without a backup you cannot log in to this account again.'**
  String get logOutBody;

  /// Log out confirmation answer (destructive). Repeats the opener's verb
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get logOutAnswer;

  /// Error when removing the key failed
  ///
  /// In en, this message translates to:
  /// **'Could not log out. Try again.'**
  String get logOutFailed;

  /// Snackbar after copying the secret key: it is marked sensitive and cleared from the clipboard after 60 seconds
  ///
  /// In en, this message translates to:
  /// **'Secret key copied. It is cleared from the clipboard in 60 seconds.'**
  String get secretKeyCopied;

  /// Tab app bar status line: the relays answer. connected = relays connected, total = relays in use
  ///
  /// In en, this message translates to:
  /// **'Online · {connected}/{total} relays'**
  String linkOnline(int connected, int total);

  /// Tab app bar status line while no relay is connected yet but one is trying
  ///
  /// In en, this message translates to:
  /// **'Connecting to relays…'**
  String get linkConnecting;

  /// Tab app bar status line when no relay is connected
  ///
  /// In en, this message translates to:
  /// **'Offline · no relay answers'**
  String get linkOffline;

  /// Header of the node selector, after logging in and from Configuración → Node
  ///
  /// In en, this message translates to:
  /// **'Choose your node'**
  String get chooseNodeTitle;

  /// Explanation under the node selector's header
  ///
  /// In en, this message translates to:
  /// **'Pick the Mostro node whose operator registered your key as a solver. You can switch nodes later in Settings.'**
  String get chooseNodeBody;

  /// App bar title of the node selector when opened from Settings
  ///
  /// In en, this message translates to:
  /// **'Node'**
  String get chooseNodeAppBar;

  /// Chip on a node from the compiled-in list of trusted Mostro communities
  ///
  /// In en, this message translates to:
  /// **'Trusted'**
  String get nodeChipTrusted;

  /// Chip on a node the solver added by its public key
  ///
  /// In en, this message translates to:
  /// **'Added by you'**
  String get nodeChipCustom;

  /// Chip on the node the app is using now
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get nodeChipActive;

  /// Button under the node list: add a node by its public key
  ///
  /// In en, this message translates to:
  /// **'Add your own node'**
  String get nodeAddOwn;

  /// Tooltip and accessible label of the info button on a node card
  ///
  /// In en, this message translates to:
  /// **'Node info'**
  String get nodeInfoTooltip;

  /// Snackbar after switching to another node
  ///
  /// In en, this message translates to:
  /// **'Now on {name}'**
  String nodeSwitched(String name);

  /// Error when saving the active node failed
  ///
  /// In en, this message translates to:
  /// **'Could not switch to this node. Try again.'**
  String get nodeSelectFailed;

  /// Error state of the node selector
  ///
  /// In en, this message translates to:
  /// **'The node list could not be loaded. Restart the app to try again.'**
  String get nodeListFailed;

  /// Title of the add-node dialog
  ///
  /// In en, this message translates to:
  /// **'Add a node'**
  String get addNodeTitle;

  /// Explanation in the add-node dialog
  ///
  /// In en, this message translates to:
  /// **'Paste the node\'s public key (npub or hex). Its operator can give it to you.'**
  String get addNodeBody;

  /// Label of the public key field in the add-node dialog
  ///
  /// In en, this message translates to:
  /// **'Public key'**
  String get addNodePubkeyLabel;

  /// Label of the optional name field in the add-node dialog
  ///
  /// In en, this message translates to:
  /// **'Name (optional)'**
  String get addNodeNameLabel;

  /// Add-node dialog confirmation
  ///
  /// In en, this message translates to:
  /// **'Add node'**
  String get addNodeAnswer;

  /// Add-node error: not a public key
  ///
  /// In en, this message translates to:
  /// **'Enter a valid public key (npub or 64 hex characters).'**
  String get nodeErrorInvalidPubkey;

  /// Add-node error: an nsec was entered
  ///
  /// In en, this message translates to:
  /// **'That is a secret key — never share it. Enter the node\'s public key.'**
  String get nodeErrorPrivateKey;

  /// Add-node error: duplicate
  ///
  /// In en, this message translates to:
  /// **'This node is already in the list.'**
  String get nodeErrorAlreadyExists;

  /// Remove-node error: the node is active
  ///
  /// In en, this message translates to:
  /// **'This is your active node. Switch to another node before removing it.'**
  String get nodeErrorActive;

  /// Node error: the local database is not available
  ///
  /// In en, this message translates to:
  /// **'Your nodes could not be saved on this device.'**
  String get nodeErrorStorage;

  /// Node error with no specific copy
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Try again.'**
  String get nodeErrorGeneric;

  /// Action on the info screen of a node the solver added
  ///
  /// In en, this message translates to:
  /// **'Remove node'**
  String get removeNodeAction;

  /// Remove-node confirmation title
  ///
  /// In en, this message translates to:
  /// **'Remove this node?'**
  String get removeNodeTitle;

  /// Remove-node confirmation body
  ///
  /// In en, this message translates to:
  /// **'It leaves your list. You can add it again with its public key.'**
  String get removeNodeBody;

  /// Remove-node confirmation answer (destructive). Repeats the opener's verb
  ///
  /// In en, this message translates to:
  /// **'Remove node'**
  String get removeNodeAnswer;

  /// Snackbar after removing a node
  ///
  /// In en, this message translates to:
  /// **'Node removed'**
  String get nodeRemoved;

  /// App bar title of the node info screen
  ///
  /// In en, this message translates to:
  /// **'Node info'**
  String get nodeInfoTitle;

  /// Primary action of the node info screen for a node that is not active
  ///
  /// In en, this message translates to:
  /// **'Use this node'**
  String get nodeInfoUse;

  /// Group header: the node's identity (public key, kind 0 profile)
  ///
  /// In en, this message translates to:
  /// **'Node'**
  String get nodeInfoGroupNode;

  /// Row label: the node's public key
  ///
  /// In en, this message translates to:
  /// **'Public key'**
  String get nodeInfoPubkey;

  /// Row label: the region of a trusted community
  ///
  /// In en, this message translates to:
  /// **'Region'**
  String get nodeInfoRegion;

  /// Row label: the website of the node's profile
  ///
  /// In en, this message translates to:
  /// **'Website'**
  String get nodeInfoWebsite;

  /// Row label: the description in the node's profile
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get nodeInfoAbout;

  /// Empty state of the node info screen: the node's kind 38385 event was not found
  ///
  /// In en, this message translates to:
  /// **'No instance info yet'**
  String get nodeInfoEmptyTitle;

  /// Empty state body of the node info screen
  ///
  /// In en, this message translates to:
  /// **'This node has not published its instance info on your relays, or they have not answered yet. It is asked for again each time you open this screen.'**
  String get nodeInfoEmptyBody;

  /// Note when fetching the node info failed but a cached copy is shown
  ///
  /// In en, this message translates to:
  /// **'The relays did not answer. This is the info last seen.'**
  String get nodeInfoRefreshFailed;

  /// Warning when the node's instance info is older than 7 days
  ///
  /// In en, this message translates to:
  /// **'This info is more than 7 days old and may be out of date.'**
  String get nodeInfoStale;

  /// Warning for a node that advertises a protocol other than v2
  ///
  /// In en, this message translates to:
  /// **'This node speaks protocol v{version}. Bosstro speaks only v2, so it cannot resolve disputes there.'**
  String nodeInfoUnsupported(int version);

  /// When the node last published its info: under a minute ago
  ///
  /// In en, this message translates to:
  /// **'Updated just now'**
  String get nodeInfoUpdatedNow;

  /// When the node last published its info
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Updated 1 minute ago} other{Updated {count} minutes ago}}'**
  String nodeInfoUpdatedMinutes(int count);

  /// When the node last published its info
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Updated 1 hour ago} other{Updated {count} hours ago}}'**
  String nodeInfoUpdatedHours(int count);

  /// When the node last published its info
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Updated 1 day ago} other{Updated {count} days ago}}'**
  String nodeInfoUpdatedDays(int count);

  /// Group header (Mostrix's Mostro Info tab)
  ///
  /// In en, this message translates to:
  /// **'Protocol'**
  String get nodeInfoGroupProtocol;

  /// Row label: kind 38385 protocol_version
  ///
  /// In en, this message translates to:
  /// **'Protocol version'**
  String get nodeInfoProtocolVersion;

  /// Row label: the transport Bosstro uses with the node
  ///
  /// In en, this message translates to:
  /// **'Wire transport'**
  String get nodeInfoTransport;

  /// Group header: the node's mostrod settings
  ///
  /// In en, this message translates to:
  /// **'Mostro daemon'**
  String get nodeInfoGroupDaemon;

  /// Row label: mostro_version
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get nodeInfoVersion;

  /// Row label: mostro_commit_hash or lnd_commit_hash
  ///
  /// In en, this message translates to:
  /// **'Commit'**
  String get nodeInfoCommit;

  /// Row label: max_order_amount, in sats
  ///
  /// In en, this message translates to:
  /// **'Max order'**
  String get nodeInfoMaxOrder;

  /// Row label: min_order_amount, in sats
  ///
  /// In en, this message translates to:
  /// **'Min order'**
  String get nodeInfoMinOrder;

  /// Row label: expiration_hours
  ///
  /// In en, this message translates to:
  /// **'Order expiration'**
  String get nodeInfoExpirationHours;

  /// Row label: expiration_seconds
  ///
  /// In en, this message translates to:
  /// **'Taken order expiration'**
  String get nodeInfoExpirationSeconds;

  /// Row label: hold_invoice_expiration_window, seconds
  ///
  /// In en, this message translates to:
  /// **'Hold invoice window'**
  String get nodeInfoHoldWindow;

  /// Row label: hold_invoice_cltv_delta, blocks
  ///
  /// In en, this message translates to:
  /// **'Hold invoice CLTV delta'**
  String get nodeInfoHoldCltv;

  /// Row label: invoice_expiration_window, seconds
  ///
  /// In en, this message translates to:
  /// **'Invoice window'**
  String get nodeInfoInvoiceWindow;

  /// Row label: max_orders_per_response
  ///
  /// In en, this message translates to:
  /// **'Max orders per response'**
  String get nodeInfoMaxOrders;

  /// Row label: the node's fee
  ///
  /// In en, this message translates to:
  /// **'Fee'**
  String get nodeInfoFee;

  /// Row label: pow, in bits
  ///
  /// In en, this message translates to:
  /// **'Required PoW'**
  String get nodeInfoPow;

  /// Row label: pow_first_contact, in bits
  ///
  /// In en, this message translates to:
  /// **'PoW on first contact'**
  String get nodeInfoPowFirst;

  /// Row label: bond_enabled
  ///
  /// In en, this message translates to:
  /// **'Anti-abuse deposits'**
  String get nodeInfoBonds;

  /// Group header: the node's LND
  ///
  /// In en, this message translates to:
  /// **'Lightning node'**
  String get nodeInfoGroupLightning;

  /// Row label: lnd_node_alias
  ///
  /// In en, this message translates to:
  /// **'Alias'**
  String get nodeInfoAlias;

  /// Row label: lnd_node_pubkey
  ///
  /// In en, this message translates to:
  /// **'Node pubkey'**
  String get nodeInfoLnPubkey;

  /// Row label: lnd_version
  ///
  /// In en, this message translates to:
  /// **'LND version'**
  String get nodeInfoLndVersion;

  /// Row label: lnd_chains
  ///
  /// In en, this message translates to:
  /// **'Chains'**
  String get nodeInfoChains;

  /// Row label: lnd_networks
  ///
  /// In en, this message translates to:
  /// **'Networks'**
  String get nodeInfoNetworks;

  /// Row label: one of lnd_uris
  ///
  /// In en, this message translates to:
  /// **'URI'**
  String get nodeInfoUri;

  /// Group header: fiat_currencies_accepted
  ///
  /// In en, this message translates to:
  /// **'Fiat currencies'**
  String get nodeInfoGroupFiat;

  /// When the node accepts every fiat currency
  ///
  /// In en, this message translates to:
  /// **'All currencies are accepted.'**
  String get nodeInfoFiatAll;

  /// A value the node does not publish
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get nodeInfoUnknown;

  /// bond_enabled true
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get nodeInfoEnabled;

  /// bond_enabled false
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get nodeInfoDisabled;

  /// An amount in satoshis. amount is formatted
  ///
  /// In en, this message translates to:
  /// **'{amount} sats'**
  String unitSats(String amount);

  /// A duration in hours
  ///
  /// In en, this message translates to:
  /// **'{count} h'**
  String unitHours(int count);

  /// A duration in seconds
  ///
  /// In en, this message translates to:
  /// **'{count} s'**
  String unitSeconds(int count);

  /// A number of blocks
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 block} other{{count} blocks}}'**
  String unitBlocks(int count);

  /// Proof-of-work difficulty in bits
  ///
  /// In en, this message translates to:
  /// **'{count} bits'**
  String unitBits(int count);

  /// A percentage. value is formatted
  ///
  /// In en, this message translates to:
  /// **'{value} %'**
  String unitPercent(String value);

  /// App bar title of the relays screen
  ///
  /// In en, this message translates to:
  /// **'Relays'**
  String get relaysTitle;

  /// Explanation at the top of the relays screen
  ///
  /// In en, this message translates to:
  /// **'Bosstro talks to your node through these relays. The relays your node announces are added for you.'**
  String get relaysBody;

  /// A relay's status
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get relayStatusConnected;

  /// A relay's status
  ///
  /// In en, this message translates to:
  /// **'Connecting'**
  String get relayStatusConnecting;

  /// A relay's status
  ///
  /// In en, this message translates to:
  /// **'Disconnected'**
  String get relayStatusDisconnected;

  /// A relay's status: the relay refused the connection (banned)
  ///
  /// In en, this message translates to:
  /// **'Refused'**
  String get relayStatusError;

  /// Where a relay came from: seeded on first launch
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get relaySourceDefault;

  /// Where a relay came from: the node's relay list
  ///
  /// In en, this message translates to:
  /// **'From your node'**
  String get relaySourceNode;

  /// Where a relay came from: the solver added it
  ///
  /// In en, this message translates to:
  /// **'Added by you'**
  String get relaySourceUser;

  /// Button on the relays screen
  ///
  /// In en, this message translates to:
  /// **'Add relay'**
  String get relayAdd;

  /// Title of the add-relay dialog
  ///
  /// In en, this message translates to:
  /// **'Add a relay'**
  String get addRelayTitle;

  /// Label of the field in the add-relay dialog
  ///
  /// In en, this message translates to:
  /// **'Relay address'**
  String get addRelayLabel;

  /// Add-relay dialog confirmation
  ///
  /// In en, this message translates to:
  /// **'Add relay'**
  String get addRelayAnswer;

  /// Tooltip and accessible label of a relay's remove button
  ///
  /// In en, this message translates to:
  /// **'Remove relay'**
  String get relayRemoveTooltip;

  /// Remove-relay confirmation title
  ///
  /// In en, this message translates to:
  /// **'Remove this relay?'**
  String get removeRelayTitle;

  /// Remove-relay confirmation body
  ///
  /// In en, this message translates to:
  /// **'Bosstro stops using it. A relay your node announced comes back only if you add it yourself.'**
  String get removeRelayBody;

  /// Remove-relay confirmation answer (destructive). Repeats the opener's verb
  ///
  /// In en, this message translates to:
  /// **'Remove relay'**
  String get removeRelayAnswer;

  /// Add-relay error: not a websocket URL
  ///
  /// In en, this message translates to:
  /// **'Enter a relay address that starts with wss://.'**
  String get relayErrorInvalidUrl;

  /// Add-relay error: duplicate
  ///
  /// In en, this message translates to:
  /// **'This relay is already in the list.'**
  String get relayErrorExists;

  /// Remove-relay error: it is the only one
  ///
  /// In en, this message translates to:
  /// **'This is your last relay. Add another before removing it.'**
  String get relayErrorLast;

  /// Error state of the relays screen
  ///
  /// In en, this message translates to:
  /// **'The relays did not start'**
  String get relaysNotRunningTitle;

  /// Error state body of the relays screen
  ///
  /// In en, this message translates to:
  /// **'Bosstro could not open its connection to the relays. Restart the app to try again.'**
  String get relaysNotRunningBody;

  /// Settings group header: the active node and its relays
  ///
  /// In en, this message translates to:
  /// **'Node'**
  String get settingsGroupNode;

  /// Settings row: opens the node selector; its value is the active node's name
  ///
  /// In en, this message translates to:
  /// **'Node'**
  String get settingsNode;

  /// Value of the Node row when no node is chosen
  ///
  /// In en, this message translates to:
  /// **'Choose'**
  String get settingsNodeNone;

  /// Settings row: opens the active node's info
  ///
  /// In en, this message translates to:
  /// **'Node info'**
  String get settingsNodeInfo;

  /// Settings row: opens the relays screen
  ///
  /// In en, this message translates to:
  /// **'Relays'**
  String get settingsRelays;

  /// Value of the Relays row: connected relays / relays in use
  ///
  /// In en, this message translates to:
  /// **'{connected}/{total}'**
  String settingsRelaysValue(int connected, int total);

  /// Disputes, Pending empty state before a node is chosen
  ///
  /// In en, this message translates to:
  /// **'Choose your node first'**
  String get pendingNoNodeTitle;

  /// Disputes, Pending empty state body before a node is chosen
  ///
  /// In en, this message translates to:
  /// **'Disputes are read from one Mostro node at a time. Pick the node where you are a solver.'**
  String get pendingNoNodeBody;

  /// Disputes, Pending empty state action: opens the node selector
  ///
  /// In en, this message translates to:
  /// **'Choose node'**
  String get pendingNoNodeAction;

  /// Screen-reader label of the node list skeleton
  ///
  /// In en, this message translates to:
  /// **'Loading nodes'**
  String get loadingNodes;

  /// Screen-reader label of the node info skeleton
  ///
  /// In en, this message translates to:
  /// **'Loading node info'**
  String get loadingNodeInfo;

  /// Screen-reader label of the relay list skeleton
  ///
  /// In en, this message translates to:
  /// **'Loading relays'**
  String get loadingRelays;

  /// Screen-reader label of the Pending list skeleton
  ///
  /// In en, this message translates to:
  /// **'Loading disputes'**
  String get loadingDisputes;

  /// Disputes, Pending state when the stored disputes cannot be read
  ///
  /// In en, this message translates to:
  /// **'Disputes could not be read'**
  String get pendingLoadErrorTitle;

  /// Explanation under pendingLoadErrorTitle
  ///
  /// In en, this message translates to:
  /// **'Something went wrong reading this node\'s disputes on this phone. Close and reopen Bosstro to try again.'**
  String get pendingLoadErrorBody;

  /// Status chip of a dispute nobody has taken yet (initiated). Shown upper-case
  ///
  /// In en, this message translates to:
  /// **'Waiting for a solver'**
  String get disputeStatusInitiated;

  /// Status chip of a dispute a solver took (in-progress). Shown upper-case
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get disputeStatusInProgress;

  /// Status chip of a dispute a solver closed by paying the buyer (settled). Shown upper-case
  ///
  /// In en, this message translates to:
  /// **'Buyer paid'**
  String get disputeStatusSettled;

  /// Status chip of a dispute a solver closed by refunding the seller (seller-refunded). Shown upper-case
  ///
  /// In en, this message translates to:
  /// **'Seller refunded'**
  String get disputeStatusSellerRefunded;

  /// Status chip of a dispute the seller ended by releasing the funds (released). Shown upper-case
  ///
  /// In en, this message translates to:
  /// **'Released by the seller'**
  String get disputeStatusReleased;

  /// Status chip of a dispute the buyer and seller ended by canceling together (cooperatively-canceled). Shown upper-case
  ///
  /// In en, this message translates to:
  /// **'Canceled by both parties'**
  String get disputeStatusCooperativelyCanceled;

  /// Who opened a dispute: the buyer
  ///
  /// In en, this message translates to:
  /// **'Opened by the buyer'**
  String get disputeOpenedByBuyer;

  /// Who opened a dispute: the seller
  ///
  /// In en, this message translates to:
  /// **'Opened by the seller'**
  String get disputeOpenedBySeller;

  /// Who opened a dispute: the node did not say
  ///
  /// In en, this message translates to:
  /// **'Opener not known'**
  String get disputeOpenedByUnknown;

  /// Age of a dispute opened less than a minute ago
  ///
  /// In en, this message translates to:
  /// **'Opened just now'**
  String get disputeOpenedJustNow;

  /// Age of a dispute, in minutes
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Opened 1 minute ago} other{Opened {count} minutes ago}}'**
  String disputeOpenedMinutesAgo(int count);

  /// Age of a dispute, in hours
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Opened 1 hour ago} other{Opened {count} hours ago}}'**
  String disputeOpenedHoursAgo(int count);

  /// Age of a dispute, in days
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Opened 1 day ago} other{Opened {count} days ago}}'**
  String disputeOpenedDaysAgo(int count);

  /// Age of a dispute whose event carries no open time
  ///
  /// In en, this message translates to:
  /// **'Open time not known'**
  String get disputeOpenedUnknown;

  /// Screen-reader label of a dispute row; id is the short dispute id
  ///
  /// In en, this message translates to:
  /// **'Dispute {id}'**
  String disputeRowLabel(String id);

  /// Answer of a dialog that only informs
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// Screen-reader hint of a Pending row: tapping it opens the take confirmation (glossary: take a dispute)
  ///
  /// In en, this message translates to:
  /// **'Take dispute'**
  String get takeDisputeHint;

  /// Title of the confirmation before taking a dispute
  ///
  /// In en, this message translates to:
  /// **'Take this dispute?'**
  String get takeDisputeTitle;

  /// Body of the take confirmation
  ///
  /// In en, this message translates to:
  /// **'You become its solver: the node tells the buyer and the seller, and the dispute moves to In progress. Take only a dispute you can follow to the end.'**
  String get takeDisputeBody;

  /// Answer of the take confirmation; repeats the opener's verb (DS-CMP-26, glossary: take a dispute)
  ///
  /// In en, this message translates to:
  /// **'Take dispute'**
  String get takeDisputeAnswer;

  /// Snackbar once the node gave the solver the dispute
  ///
  /// In en, this message translates to:
  /// **'Dispute taken. It is under In progress.'**
  String get takeTakenSnack;

  /// Label of the action in the Disputes header that opens Recover a dispute
  ///
  /// In en, this message translates to:
  /// **'Recover'**
  String get recoverAction;

  /// Title of the Recover a dispute screen, and the link to it
  ///
  /// In en, this message translates to:
  /// **'Recover a dispute'**
  String get recoverTitle;

  /// Note at the top of Recover a dispute
  ///
  /// In en, this message translates to:
  /// **'The node does not publish who holds a dispute. So this list shows every dispute in progress on this node that is not among yours on this phone: yours whose answer was lost, and other solvers\'. Recover them one at a time.'**
  String get recoverNote;

  /// Recover a dispute with no candidate
  ///
  /// In en, this message translates to:
  /// **'Nothing to recover'**
  String get recoverEmptyTitle;

  /// Explanation under recoverEmptyTitle
  ///
  /// In en, this message translates to:
  /// **'No dispute in progress on this node is missing from yours.'**
  String get recoverEmptyBody;

  /// Screen-reader hint of a Recover row: tapping it opens the recover confirmation
  ///
  /// In en, this message translates to:
  /// **'Recover dispute'**
  String get recoverDisputeHint;

  /// Title of the confirmation before recovering a dispute
  ///
  /// In en, this message translates to:
  /// **'Recover this dispute?'**
  String get recoverDisputeTitle;

  /// Body of the recover confirmation; warns about the take-over
  ///
  /// In en, this message translates to:
  /// **'Bosstro asks the node for this dispute again. If it is yours, the node sends its data back. If another solver holds it, the node says no, unless that solver is read-only, like Serbero, and your key can pay the buyer and refund the seller: then the dispute becomes yours (a take-over).'**
  String get recoverDisputeBody;

  /// Answer of the recover confirmation; repeats the opener's verb (DS-CMP-26)
  ///
  /// In en, this message translates to:
  /// **'Recover dispute'**
  String get recoverDisputeAnswer;

  /// Snackbar once the node gave the dispute back
  ///
  /// In en, this message translates to:
  /// **'Dispute recovered. It is under In progress.'**
  String get recoverTakenSnack;

  /// Banner on Pending and take outcome when the node refused a dispute waiting for a solver
  ///
  /// In en, this message translates to:
  /// **'You are not a solver on this node'**
  String get notSolverTitle;

  /// Body under notSolverTitle
  ///
  /// In en, this message translates to:
  /// **'Switch to your node to resolve disputes. If this is your node, send your npub to its operator.'**
  String get notSolverBody;

  /// Action that opens the node selector from the not-a-solver banner or outcome
  ///
  /// In en, this message translates to:
  /// **'Switch node'**
  String get switchNodeAction;

  /// Take outcome when the node refused a dispute a solver already holds
  ///
  /// In en, this message translates to:
  /// **'Another solver holds this dispute'**
  String get cannotTakeOverTitle;

  /// Body under cannotTakeOverTitle
  ///
  /// In en, this message translates to:
  /// **'Only a dispute held by a read-only solver, like Serbero, can be taken over, and only by a solver who can pay the buyer and refund the seller.'**
  String get cannotTakeOverBody;

  /// Take outcome for any other refusal
  ///
  /// In en, this message translates to:
  /// **'The node did not give you this dispute'**
  String get takeRefusedTitle;

  /// Body under takeRefusedTitle
  ///
  /// In en, this message translates to:
  /// **'It refused the request. Try again later, or ask the node\'s operator.'**
  String get takeRefusedBody;

  /// Body under takeRefusedTitle when the node did not find the order
  ///
  /// In en, this message translates to:
  /// **'The node no longer has this dispute\'s order.'**
  String get takeRefusedNotFoundBody;

  /// Take outcome when no answer arrived in time
  ///
  /// In en, this message translates to:
  /// **'The node did not answer'**
  String get noAnswerTitle;

  /// Body under noAnswerTitle
  ///
  /// In en, this message translates to:
  /// **'Your request may have reached it all the same, so Bosstro did not send it again. In a moment, look under In progress, or ask again from Recover a dispute.'**
  String get noAnswerBody;

  /// Take outcome when the request could not leave
  ///
  /// In en, this message translates to:
  /// **'The request was not sent'**
  String get takeFailedTitle;

  /// Body under takeFailedTitle
  ///
  /// In en, this message translates to:
  /// **'No relay took it. Check your connection and the relays, then try again.'**
  String get takeFailedBody;

  /// Body under takeFailedTitle when a take, a resolution or an order lookup was not sent because no solver key is loaded
  ///
  /// In en, this message translates to:
  /// **'No secret key is loaded, so nothing was sent. Close Bosstro and open it again.'**
  String get requestNoKeyBody;

  /// Body under takeFailedTitle when a take, a resolution or an order lookup was not sent because no node is chosen
  ///
  /// In en, this message translates to:
  /// **'No node is chosen, so nothing was sent. Choose your node in Settings.'**
  String get requestNoNodeBody;

  /// Body under takeFailedTitle when a take of this dispute is pending
  ///
  /// In en, this message translates to:
  /// **'A request for this dispute is already waiting for the node\'s answer.'**
  String get takeAlreadyTakingBody;

  /// Body under takeFailedTitle when the dispute closed meanwhile
  ///
  /// In en, this message translates to:
  /// **'This dispute is closed: there is nothing to take.'**
  String get takeClosedBody;

  /// Body under takeFailedTitle when the dispute is not stored
  ///
  /// In en, this message translates to:
  /// **'This dispute is not among this node\'s disputes on this phone.'**
  String get takeUnknownBody;

  /// Body under takeFailedTitle when the node does not speak protocol 2
  ///
  /// In en, this message translates to:
  /// **'This node announces another protocol version. Bosstro talks to nodes on protocol 2 only.'**
  String get takeProtocolBody;

  /// Body under takeFailedTitle when the node's kind 38385 (its settings, with the proof of work a request needs) was never read
  ///
  /// In en, this message translates to:
  /// **'Bosstro could not read this node\'s settings, so it does not know the proof of work the node asks for. Check the relays and try again.'**
  String get takeNodeInfoBody;

  /// How long ago the solver took a dispute, under a minute
  ///
  /// In en, this message translates to:
  /// **'Taken just now'**
  String get disputeTakenJustNow;

  /// How long ago the solver took a dispute, in minutes
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Taken 1 minute ago} other{Taken {count} minutes ago}}'**
  String disputeTakenMinutesAgo(int count);

  /// How long ago the solver took a dispute, in hours
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Taken 1 hour ago} other{Taken {count} hours ago}}'**
  String disputeTakenHoursAgo(int count);

  /// How long ago the solver took a dispute, in days
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Taken 1 day ago} other{Taken {count} days ago}}'**
  String disputeTakenDaysAgo(int count);

  /// A dispute's trade amount in sats; amount is already formatted
  ///
  /// In en, this message translates to:
  /// **'{amount} sats'**
  String disputeAmountSats(String amount);

  /// A dispute's fiat amount; amount is already formatted, code is the currency (EUR)
  ///
  /// In en, this message translates to:
  /// **'{amount} {code}'**
  String disputeAmountFiat(String amount, String code);

  /// A taken dispute whose amount the node did not send
  ///
  /// In en, this message translates to:
  /// **'Amount not known'**
  String get disputeAmountUnknown;

  /// Settings row: whether the node let this key take a dispute
  ///
  /// In en, this message translates to:
  /// **'Solver on this node'**
  String get settingsSolverStatus;

  /// Value of settingsSolverStatus
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get settingsSolverYes;

  /// Value of settingsSolverStatus
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get settingsSolverNo;

  /// Settings row: what the solver key may do on this node
  ///
  /// In en, this message translates to:
  /// **'Permission'**
  String get settingsPermission;

  /// Permission value: read-only solver (takes and chats, never pays or refunds)
  ///
  /// In en, this message translates to:
  /// **'Mediate only'**
  String get permissionRead;

  /// Permission value: read-write solver
  ///
  /// In en, this message translates to:
  /// **'Mediate, pay and refund'**
  String get permissionReadWrite;

  /// App bar title of the dispute detail
  ///
  /// In en, this message translates to:
  /// **'Dispute'**
  String get disputeDetailTitle;

  /// Segment of the dispute detail with the dispute's data
  ///
  /// In en, this message translates to:
  /// **'Info'**
  String get detailSegmentInfo;

  /// Segment of the dispute detail with the chat with the buyer
  ///
  /// In en, this message translates to:
  /// **'Buyer'**
  String get detailSegmentBuyer;

  /// Segment of the dispute detail with the chat with the seller
  ///
  /// In en, this message translates to:
  /// **'Seller'**
  String get detailSegmentSeller;

  /// Screen-reader label of the Info / Buyer / Seller control
  ///
  /// In en, this message translates to:
  /// **'Dispute sections'**
  String get detailSegmentsLabel;

  /// Data row: the dispute id, copyable
  ///
  /// In en, this message translates to:
  /// **'Dispute ID'**
  String get detailDisputeId;

  /// Data row: the order id, copyable
  ///
  /// In en, this message translates to:
  /// **'Order ID'**
  String get detailOrderId;

  /// Data row: the dispute's status
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get detailStatus;

  /// Data row: who opened the dispute
  ///
  /// In en, this message translates to:
  /// **'Opened by'**
  String get detailOpenedBy;

  /// Data row: when the dispute was opened
  ///
  /// In en, this message translates to:
  /// **'Opened'**
  String get detailOpenedAt;

  /// Data row: when this solver took the dispute
  ///
  /// In en, this message translates to:
  /// **'Taken'**
  String get detailTakenAt;

  /// Data row: the order's amount in sats
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get detailAmount;

  /// Data row: the fiat currency the order trades in (its code, as CUP or EUR)
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get detailCurrency;

  /// Title of the Info card that folds the dispute's, the order's and the parties' facts; closed by default
  ///
  /// In en, this message translates to:
  /// **'Dispute information'**
  String get detailFactsTitle;

  /// Data row: the order's fiat amount
  ///
  /// In en, this message translates to:
  /// **'Fiat amount'**
  String get detailFiatAmount;

  /// Data row: the order's payment method
  ///
  /// In en, this message translates to:
  /// **'Payment method'**
  String get detailPaymentMethod;

  /// Data row: the order's premium over the market price
  ///
  /// In en, this message translates to:
  /// **'Premium'**
  String get detailPremium;

  /// Data row: the node's fee for the order, in sats. It is what each party pays, so half of what the node charges for the order
  ///
  /// In en, this message translates to:
  /// **'Node fee (each party)'**
  String get detailFee;

  /// Data row: whether the order was a buy or a sell order
  ///
  /// In en, this message translates to:
  /// **'Order type'**
  String get detailOrderKind;

  /// Data row: the buyer's trade public key, copyable
  ///
  /// In en, this message translates to:
  /// **'Buyer\'s trade key'**
  String get detailBuyerKey;

  /// Data row: the seller's trade public key, copyable
  ///
  /// In en, this message translates to:
  /// **'Seller\'s trade key'**
  String get detailSellerKey;

  /// Value of the Opened by row: the buyer
  ///
  /// In en, this message translates to:
  /// **'Buyer'**
  String get detailPartyBuyer;

  /// Value of the Opened by row: the seller
  ///
  /// In en, this message translates to:
  /// **'Seller'**
  String get detailPartySeller;

  /// Value of a data row the node did not send
  ///
  /// In en, this message translates to:
  /// **'Not known'**
  String get detailPartyUnknown;

  /// Value of the Order type row: a buy order
  ///
  /// In en, this message translates to:
  /// **'Buy order'**
  String get detailOrderKindBuy;

  /// Value of the Order type row: a sell order
  ///
  /// In en, this message translates to:
  /// **'Sell order'**
  String get detailOrderKindSell;

  /// Value of the Premium row
  ///
  /// In en, this message translates to:
  /// **'{value} %'**
  String detailPremiumValue(String value);

  /// Shown in the detail when the dispute is no longer held by this solver key
  ///
  /// In en, this message translates to:
  /// **'This dispute is not yours now'**
  String get detailNotYoursTitle;

  /// Explanation under detailNotYoursTitle
  ///
  /// In en, this message translates to:
  /// **'The node reopened it, or it belongs to another key. It is no longer among your disputes.'**
  String get detailNotYoursBody;

  /// Sender label of the solver's own chat message
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get chatSenderYou;

  /// Sender label of a chat message from the buyer
  ///
  /// In en, this message translates to:
  /// **'Buyer'**
  String get chatSenderBuyer;

  /// Sender label of a chat message from the seller
  ///
  /// In en, this message translates to:
  /// **'Seller'**
  String get chatSenderSeller;

  /// Empty state title of the chat with the buyer
  ///
  /// In en, this message translates to:
  /// **'No messages with the buyer'**
  String get chatEmptyBuyerTitle;

  /// Empty state title of the chat with the seller
  ///
  /// In en, this message translates to:
  /// **'No messages with the seller'**
  String get chatEmptySellerTitle;

  /// Empty state explanation of a dispute chat
  ///
  /// In en, this message translates to:
  /// **'Only you and this party can read this conversation. The other party does not see it.'**
  String get chatEmptyBody;

  /// Shown instead of a chat when the node did not name the party's trade key
  ///
  /// In en, this message translates to:
  /// **'No chat with this party'**
  String get chatNoPartyKeyTitle;

  /// Explanation under chatNoPartyKeyTitle
  ///
  /// In en, this message translates to:
  /// **'The node\'s answer to the take did not include this party\'s key, so Bosstro cannot reach them.'**
  String get chatNoPartyKeyBody;

  /// Shown in place of the message field when the dispute is over
  ///
  /// In en, this message translates to:
  /// **'This dispute is closed. The chat is read only.'**
  String get chatClosedNote;

  /// Placeholder of the message field in the chat with the buyer
  ///
  /// In en, this message translates to:
  /// **'Write to the buyer'**
  String get chatComposerBuyerHint;

  /// Placeholder of the message field in the chat with the seller
  ///
  /// In en, this message translates to:
  /// **'Write to the seller'**
  String get chatComposerSellerHint;

  /// Tooltip and screen-reader label of the send button
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get chatSend;

  /// Status of a solver's message being sent
  ///
  /// In en, this message translates to:
  /// **'Sending…'**
  String get chatSending;

  /// Status of a solver's message no relay took
  ///
  /// In en, this message translates to:
  /// **'Not sent'**
  String get chatNotSent;

  /// Action on a message that was not sent: send it again
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get chatRetry;

  /// Shown under the message field when the message is over the limit
  ///
  /// In en, this message translates to:
  /// **'The message is too long. Split it in two.'**
  String get chatErrorTooLong;

  /// Shown under the message field when the dispute closed meanwhile
  ///
  /// In en, this message translates to:
  /// **'This dispute is closed. The chat is read only.'**
  String get chatErrorClosed;

  /// Shown under the message field when the relays are not running
  ///
  /// In en, this message translates to:
  /// **'Not connected to any relay. Check your connection.'**
  String get chatErrorNoRelays;

  /// Shown under the message field when the dispute is no longer held by this key
  ///
  /// In en, this message translates to:
  /// **'This dispute is no longer yours.'**
  String get chatErrorNotYours;

  /// Shown under the message field for any other refusal
  ///
  /// In en, this message translates to:
  /// **'The message could not be sent.'**
  String get chatErrorGeneric;

  /// Screen-reader label of the chat's loading skeleton
  ///
  /// In en, this message translates to:
  /// **'Loading the messages'**
  String get chatLoading;

  /// Screen-reader label of one chat message
  ///
  /// In en, this message translates to:
  /// **'{sender}, {time}: {text}'**
  String chatMessageLabel(String sender, String time, String text);

  /// Screen-reader hint of a row of the disputes in progress
  ///
  /// In en, this message translates to:
  /// **'Open the dispute'**
  String get openDisputeHint;

  /// Tooltip and screen-reader label of the attach button in the chat
  ///
  /// In en, this message translates to:
  /// **'Attach a file'**
  String get chatAttach;

  /// Title of the sheet that asks where a file comes from
  ///
  /// In en, this message translates to:
  /// **'Attach'**
  String get attachSheetTitle;

  /// Attach sheet row: pick an image
  ///
  /// In en, this message translates to:
  /// **'Photo from the gallery'**
  String get attachSourcePhoto;

  /// Attach sheet row: open the camera
  ///
  /// In en, this message translates to:
  /// **'Take a photo'**
  String get attachSourceCamera;

  /// Attach sheet row: pick a PDF
  ///
  /// In en, this message translates to:
  /// **'PDF document'**
  String get attachSourcePdf;

  /// Note at the foot of the attach sheet
  ///
  /// In en, this message translates to:
  /// **'The file is encrypted on this device. Only you and this party can open it. JPEG, PNG or PDF, up to 25 MB.'**
  String get attachSheetNote;

  /// Title of the confirmation before a file is sent
  ///
  /// In en, this message translates to:
  /// **'Send this file?'**
  String get attachConfirmTitle;

  /// Body of the confirmation before a file is sent to the buyer
  ///
  /// In en, this message translates to:
  /// **'{name} ({size}) goes to the buyer, encrypted. A photo is sent without its location or camera details.'**
  String attachConfirmBuyer(String name, String size);

  /// Body of the confirmation before a file is sent to the seller
  ///
  /// In en, this message translates to:
  /// **'{name} ({size}) goes to the seller, encrypted. A photo is sent without its location or camera details.'**
  String attachConfirmSeller(String name, String size);

  /// A picked or received file is over the limit
  ///
  /// In en, this message translates to:
  /// **'The file is over 25 MB.'**
  String get attachmentTooLarge;

  /// The picked file is not a JPEG, PNG or PDF
  ///
  /// In en, this message translates to:
  /// **'Only JPEG and PNG images and PDF documents can be sent.'**
  String get attachmentUnsupported;

  /// The image does not decode
  ///
  /// In en, this message translates to:
  /// **'The image could not be read.'**
  String get attachmentInvalidImage;

  /// The picked file could not be read, or the camera was refused
  ///
  /// In en, this message translates to:
  /// **'The file could not be read.'**
  String get attachmentReadFailed;

  /// No file server took the upload
  ///
  /// In en, this message translates to:
  /// **'The file could not be uploaded. Check your connection and try again.'**
  String get attachmentUploadFailed;

  /// Any other refusal of a file being sent
  ///
  /// In en, this message translates to:
  /// **'The file could not be sent.'**
  String get attachmentSendFailed;

  /// Status of a file being sent
  ///
  /// In en, this message translates to:
  /// **'Encrypting and sending…'**
  String get attachmentUploading;

  /// Action on a file that was not sent: forget it
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get attachmentDiscard;

  /// Screen-reader label of the skeleton shown while a file downloads and decrypts
  ///
  /// In en, this message translates to:
  /// **'Decrypting the file'**
  String get attachmentLoading;

  /// The downloaded file is not the one the message names, or does not open with the conversation's key
  ///
  /// In en, this message translates to:
  /// **'The file could not be verified.'**
  String get attachmentNotVerified;

  /// The download of a file failed
  ///
  /// In en, this message translates to:
  /// **'The file could not be downloaded.'**
  String get attachmentDownloadFailed;

  /// A received file is not a JPEG, PNG or PDF
  ///
  /// In en, this message translates to:
  /// **'This type of file cannot be opened here.'**
  String get attachmentUnsupportedReceived;

  /// Any other failure to open a file
  ///
  /// In en, this message translates to:
  /// **'The file could not be opened.'**
  String get attachmentOpenFailed;

  /// Screen-reader label of an image in the chat
  ///
  /// In en, this message translates to:
  /// **'Image {name}'**
  String attachmentImageLabel(String name);

  /// Screen-reader hint of an image in the chat
  ///
  /// In en, this message translates to:
  /// **'Open the image'**
  String get attachmentOpenImage;

  /// Action: save the file where the solver chooses
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get attachmentSave;

  /// Screen-reader hint of a file in the chat
  ///
  /// In en, this message translates to:
  /// **'Save the file'**
  String get attachmentSaveHint;

  /// Confirmation that a file was saved
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get attachmentSaved;

  /// Saving a file failed
  ///
  /// In en, this message translates to:
  /// **'The file could not be saved.'**
  String get attachmentSaveFailed;

  /// Screen-reader label of a file in the chat
  ///
  /// In en, this message translates to:
  /// **'{name}, {details}'**
  String attachmentFileLabel(String name, String details);

  /// Screen-reader hint of the full-screen image
  ///
  /// In en, this message translates to:
  /// **'Pinch to zoom'**
  String get attachmentViewerZoomHint;

  /// Title of the dispute's buyer–seller chat, read with a chat key (Info card and its screen)
  ///
  /// In en, this message translates to:
  /// **'Chat between the parties'**
  String get observerTitle;

  /// Info card: the buyer sent this solver the key of the buyer–seller chat
  ///
  /// In en, this message translates to:
  /// **'The buyer shared their chat key on {date}.'**
  String observerSharedByBuyer(String date);

  /// Info card: the seller sent this solver the key of the buyer–seller chat
  ///
  /// In en, this message translates to:
  /// **'The seller shared their chat key on {date}.'**
  String observerSharedBySeller(String date);

  /// Info card: a chat key pasted by the solver is held (until the app closes)
  ///
  /// In en, this message translates to:
  /// **'You pasted a chat key for this dispute.'**
  String get observerPastedKey;

  /// Info card: messages are stored but no key is held any more (a pasted key is forgotten when the app closes)
  ///
  /// In en, this message translates to:
  /// **'Messages kept from an earlier read. Paste the chat key again to look for new ones.'**
  String get observerStoredOnly;

  /// Info card and empty screen: no chat key is known for this dispute
  ///
  /// In en, this message translates to:
  /// **'Neither party has shared their chat key yet. If one sends it to you another way, paste it here.'**
  String get observerNoKey;

  /// Info card action: open the buyer–seller chat
  ///
  /// In en, this message translates to:
  /// **'Read the chat between the parties'**
  String get observerReadAction;

  /// Action: paste the key of the buyer–seller chat that a party sent
  ///
  /// In en, this message translates to:
  /// **'Paste a chat key'**
  String get observerPasteAction;

  /// Action: ask the relays for the buyer–seller chat again
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get observerRefresh;

  /// Note pinned under the buyer–seller chat, in place of a message field: there is none, the chat is read only
  ///
  /// In en, this message translates to:
  /// **'Read only, with the key the buyer shared.'**
  String get observerReadOnlyBuyer;

  /// Note pinned under the buyer–seller chat, in place of a message field: there is none, the chat is read only
  ///
  /// In en, this message translates to:
  /// **'Read only, with the key the seller shared.'**
  String get observerReadOnlySeller;

  /// Note pinned under the buyer–seller chat, in place of a message field: there is none, the chat is read only
  ///
  /// In en, this message translates to:
  /// **'Read only, with the key both parties shared.'**
  String get observerReadOnlyBoth;

  /// Note pinned under the buyer–seller chat, in place of a message field: there is none, the chat is read only
  ///
  /// In en, this message translates to:
  /// **'Read only, with a key you pasted.'**
  String get observerReadOnlyPasted;

  /// Note pinned under the buyer–seller chat when no key is held any more
  ///
  /// In en, this message translates to:
  /// **'Read only: messages from an earlier read.'**
  String get observerReadOnlyStored;

  /// Empty buyer–seller chat: no key is known
  ///
  /// In en, this message translates to:
  /// **'No chat key yet'**
  String get observerNoKeyTitle;

  /// The chat key opened nothing of this dispute's buyer or seller
  ///
  /// In en, this message translates to:
  /// **'The key opens no message of this dispute'**
  String get observerOpensNothingTitle;

  /// Why the chat key opened nothing; the date is where the read starts (a week before the dispute opened)
  ///
  /// In en, this message translates to:
  /// **'No message of this dispute\'s buyer or seller since {date} opens with it. It may be another trade\'s key, or they did not write in that time.'**
  String observerOpensNothingBody(String date);

  /// Reading the buyer–seller chat failed
  ///
  /// In en, this message translates to:
  /// **'The relays could not be asked'**
  String get observerReadFailedTitle;

  /// Reading the buyer–seller chat failed
  ///
  /// In en, this message translates to:
  /// **'Check the connection and try again.'**
  String get observerReadFailedBody;

  /// The node's answer to the take named no trade key, so no message can be attributed
  ///
  /// In en, this message translates to:
  /// **'The parties are not known'**
  String get observerNoPartyKeysTitle;

  /// The node's answer to the take named no trade key, so no message can be attributed
  ///
  /// In en, this message translates to:
  /// **'The node did not name the trade keys of the buyer and the seller, so no message can be shown as theirs.'**
  String get observerNoPartyKeysBody;

  /// Title of the dialog that takes a chat key
  ///
  /// In en, this message translates to:
  /// **'Paste a chat key'**
  String get observerPasteTitle;

  /// Body of the dialog that takes a chat key
  ///
  /// In en, this message translates to:
  /// **'A party can send you the key of their chat with the other party. With it you read that chat; you can never write in it.'**
  String get observerPasteBody;

  /// Placeholder of the chat key field
  ///
  /// In en, this message translates to:
  /// **'64 hexadecimal characters'**
  String get observerPasteHint;

  /// Answer of the dialog that takes a chat key: check it and read
  ///
  /// In en, this message translates to:
  /// **'Read the chat'**
  String get observerPasteConfirm;

  /// Error under the chat key field: not the format
  ///
  /// In en, this message translates to:
  /// **'That is not a chat key: it is 64 hexadecimal characters, alone or after “Shared key: ”.'**
  String get observerInvalidKey;

  /// Error under the chat key field: it opened nothing
  ///
  /// In en, this message translates to:
  /// **'The key opens no message of this dispute since {date}.'**
  String observerOpensNothingShort(String date);

  /// Error: the dispute is not held by this key on the active node
  ///
  /// In en, this message translates to:
  /// **'This dispute is no longer yours on this node.'**
  String get observerNotYours;

  /// A file in the buyer–seller chat: the chat key does not decrypt files
  ///
  /// In en, this message translates to:
  /// **'It cannot be opened with a chat key.'**
  String get observerFileLocked;

  /// A file the buyer sent in the buyer–seller chat: how the solver can get it
  ///
  /// In en, this message translates to:
  /// **'Ask the buyer to send it to you in your chat with them.'**
  String get observerFileAdviceBuyer;

  /// A file the seller sent in the buyer–seller chat: how the solver can get it
  ///
  /// In en, this message translates to:
  /// **'Ask the seller to send it to you in your chat with them.'**
  String get observerFileAdviceSeller;

  /// Type of a file that cannot be opened: an image
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get observerFileImage;

  /// Type of a file that cannot be opened, when it declares none
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get observerFileOther;

  /// Dispute detail, Info: title of the card with the two resolution actions
  ///
  /// In en, this message translates to:
  /// **'Resolve the dispute'**
  String get resolveCardTitle;

  /// Under resolveCardTitle
  ///
  /// In en, this message translates to:
  /// **'Once you have heard both parties, decide where the sats go. It cannot be undone.'**
  String get resolveCardBody;

  /// Opens the settle confirmation (glossary: pay the buyer = settle)
  ///
  /// In en, this message translates to:
  /// **'Pay the buyer'**
  String get payBuyerAction;

  /// Opens the cancel confirmation (glossary: refund the seller = cancel)
  ///
  /// In en, this message translates to:
  /// **'Refund the seller'**
  String get refundSellerAction;

  /// The destructive answer of the settle confirmation; same wording as payBuyerAction (DS-CMP-26)
  ///
  /// In en, this message translates to:
  /// **'Pay the buyer'**
  String get payBuyerAnswer;

  /// The destructive answer of the cancel confirmation; same wording as refundSellerAction (DS-CMP-26)
  ///
  /// In en, this message translates to:
  /// **'Refund the seller'**
  String get refundSellerAnswer;

  /// Shown above the resolution actions when the node said this key is a read-only solver
  ///
  /// In en, this message translates to:
  /// **'Your solver key can mediate on this node but not pay or refund. Ask the operator for read-write permission.'**
  String get resolveReadOnlyNote;

  /// Shown above the resolution actions while a settle request got no answer in time
  ///
  /// In en, this message translates to:
  /// **'Your request to pay the buyer got no answer. The node may have paid all the same: check the dispute\'s status before you try again.'**
  String get resolveUnansweredPayNote;

  /// Shown above the resolution actions while a cancel request got no answer in time
  ///
  /// In en, this message translates to:
  /// **'Your request to refund the seller got no answer. The node may have refunded all the same: check the dispute\'s status before you try again.'**
  String get resolveUnansweredRefundNote;

  /// Title of the full-screen settle confirmation
  ///
  /// In en, this message translates to:
  /// **'Pay the buyer?'**
  String get payBuyerTitle;

  /// Title of the full-screen cancel confirmation
  ///
  /// In en, this message translates to:
  /// **'Refund the seller?'**
  String get refundSellerTitle;

  /// Settle confirmation: label above the amount
  ///
  /// In en, this message translates to:
  /// **'The buyer receives'**
  String get payBuyerRecipient;

  /// Cancel confirmation: label above the amount
  ///
  /// In en, this message translates to:
  /// **'The seller gets back'**
  String get refundSellerRecipient;

  /// Settle confirmation: how the amount is made up; both are formatted sat amounts
  ///
  /// In en, this message translates to:
  /// **'The order\'s {amount} less the node\'s fee of {fee}.'**
  String payBuyerBreakdown(String amount, String fee);

  /// Cancel confirmation: how the amount is made up; both are formatted sat amounts
  ///
  /// In en, this message translates to:
  /// **'The order\'s {amount} plus the node\'s fee of {fee}, as the seller locked them.'**
  String refundSellerBreakdown(String amount, String fee);

  /// Confirmation: the fiat side of the trade, e.g. "50 EUR"
  ///
  /// In en, this message translates to:
  /// **'Trade: {fiat}'**
  String resolveTradeFiat(String fiat);

  /// Settle confirmation: what happens to the other party
  ///
  /// In en, this message translates to:
  /// **'The seller\'s hold invoice is settled: the seller does not get these sats back.'**
  String get payBuyerOtherSide;

  /// Cancel confirmation: what happens to the other party
  ///
  /// In en, this message translates to:
  /// **'The seller\'s hold invoice is canceled: the buyer receives nothing from this trade.'**
  String get refundSellerOtherSide;

  /// Confirmation: the node's info is missing or does not say whether it uses anti-abuse bonds, so no slash can be chosen and none is sent
  ///
  /// In en, this message translates to:
  /// **'Bosstro does not know whether this node uses deposits: its info could not be read or does not say. If there are any, none is slashed.'**
  String get resolveBondsUnknown;

  /// Confirmation: the irreversibility warning, in red
  ///
  /// In en, this message translates to:
  /// **'This cannot be undone. Once sent, Bosstro never sends it again by itself.'**
  String get resolveIrreversible;

  /// Confirmation: shown while the request waits for the node
  ///
  /// In en, this message translates to:
  /// **'Waiting for the node\'s answer. Keep Bosstro open.'**
  String get resolveWaiting;

  /// Result: the node confirmed the settle
  ///
  /// In en, this message translates to:
  /// **'Resolved: you paid the buyer'**
  String get resolvedPaidTitle;

  /// Under resolvedPaidTitle
  ///
  /// In en, this message translates to:
  /// **'The node settled the seller\'s hold invoice and pays the buyer. The dispute is closed.'**
  String get resolvedPaidBody;

  /// Result: the node confirmed the cancel
  ///
  /// In en, this message translates to:
  /// **'Resolved: you refunded the seller'**
  String get resolvedRefundedTitle;

  /// Under resolvedRefundedTitle
  ///
  /// In en, this message translates to:
  /// **'The node canceled the seller\'s hold invoice: the sats go back to the seller. The dispute is closed.'**
  String get resolvedRefundedBody;

  /// Result: CooperativeCancelAccepted
  ///
  /// In en, this message translates to:
  /// **'The parties had already canceled'**
  String get resolvedCoopTitle;

  /// Under resolvedCoopTitle
  ///
  /// In en, this message translates to:
  /// **'Buyer and seller canceled the trade between them before your request, so nothing was paid or refunded by you. The dispute is closed.'**
  String get resolvedCoopBody;

  /// Result: NotAuthorized (read-only solver)
  ///
  /// In en, this message translates to:
  /// **'You cannot pay or refund on this node'**
  String get readOnlySolverTitle;

  /// Result: the node said the dispute is not this key's (taken over)
  ///
  /// In en, this message translates to:
  /// **'Another solver holds this dispute now'**
  String get takenOverTitle;

  /// Under takenOverTitle
  ///
  /// In en, this message translates to:
  /// **'The node gave it to another solver, so nothing was paid or refunded. It is no longer among your disputes.'**
  String get takenOverBody;

  /// Result: refused by the order's status
  ///
  /// In en, this message translates to:
  /// **'This order is no longer in dispute'**
  String get notInDisputeTitle;

  /// Under notInDisputeTitle
  ///
  /// In en, this message translates to:
  /// **'It was paid, refunded or released already, perhaps by an earlier request whose answer was lost. The dispute\'s status will say how it ended.'**
  String get notInDisputeBody;

  /// Result: another refusal
  ///
  /// In en, this message translates to:
  /// **'The node refused the request'**
  String get resolveRefusedTitle;

  /// Under resolveRefusedTitle
  ///
  /// In en, this message translates to:
  /// **'Nothing was paid or refunded. Try again later, or ask the node\'s operator.'**
  String get resolveRefusedBody;

  /// Result: no answer in time (title is noAnswerTitle)
  ///
  /// In en, this message translates to:
  /// **'It may have acted all the same: the sats may have moved. Bosstro did not send the request again. Check the dispute\'s status before you try again; it changes as soon as the node publishes it.'**
  String get resolveNoAnswerBody;

  /// Not sent: the dispute is closed already
  ///
  /// In en, this message translates to:
  /// **'This dispute is closed: there is nothing to resolve.'**
  String get resolveClosedBody;

  /// Not sent: the take named no order id
  ///
  /// In en, this message translates to:
  /// **'Bosstro does not know this dispute\'s order, and the request needs it. Recover the dispute to read it again.'**
  String get resolveNoOrderBody;

  /// Result: the one action, back to the dispute detail
  ///
  /// In en, this message translates to:
  /// **'Back to the dispute'**
  String get resolveBackToDispute;

  /// Result after a take-over: back to the In progress list
  ///
  /// In en, this message translates to:
  /// **'Go to Disputes'**
  String get resolveGoToDisputes;

  /// A closed dispute this key resolved by paying the buyer
  ///
  /// In en, this message translates to:
  /// **'You paid the buyer'**
  String get closedPaidBuyer;

  /// A closed dispute this key resolved by refunding the seller
  ///
  /// In en, this message translates to:
  /// **'You refunded the seller'**
  String get closedRefundedSeller;

  /// A closed dispute: CooperativeCancelAccepted answered this key's request
  ///
  /// In en, this message translates to:
  /// **'The parties canceled it before your decision'**
  String get closedCooperatively;

  /// Dispute detail, Info: row with how a closed dispute ended
  ///
  /// In en, this message translates to:
  /// **'Result'**
  String get detailResult;

  /// Confirmation: heading of the anti-abuse bond choice, on a node that uses bonds
  ///
  /// In en, this message translates to:
  /// **'Deposits'**
  String get bondsTitle;

  /// Confirmation: under bondsTitle
  ///
  /// In en, this message translates to:
  /// **'This node uses anti-abuse deposits. Choose whose is slashed, if anyone\'s. It goes in the same request.'**
  String get bondsPickerHint;

  /// Bond choice: release both bonds (the default)
  ///
  /// In en, this message translates to:
  /// **'Don\'t slash'**
  String get bondNoSlash;

  /// Under bondNoSlash
  ///
  /// In en, this message translates to:
  /// **'Every deposit goes back to its owner.'**
  String get bondNoSlashDetail;

  /// Bond choice: the buyer loses their bond
  ///
  /// In en, this message translates to:
  /// **'Slash the buyer'**
  String get bondSlashBuyer;

  /// Under bondSlashBuyer
  ///
  /// In en, this message translates to:
  /// **'The buyer loses their deposit; the seller can claim their share.'**
  String get bondSlashBuyerDetail;

  /// Bond choice: the seller loses their bond
  ///
  /// In en, this message translates to:
  /// **'Slash the seller'**
  String get bondSlashSeller;

  /// Under bondSlashSeller
  ///
  /// In en, this message translates to:
  /// **'The seller loses their deposit; the buyer can claim their share.'**
  String get bondSlashSellerDetail;

  /// Bond choice: both parties lose their bond
  ///
  /// In en, this message translates to:
  /// **'Slash both'**
  String get bondSlashBoth;

  /// Under bondSlashBoth
  ///
  /// In en, this message translates to:
  /// **'Both lose their deposit.'**
  String get bondSlashBothDetail;

  /// Result: the node refused the slash of a party without a bond; nothing was resolved
  ///
  /// In en, this message translates to:
  /// **'That party posted no deposit'**
  String get bondNotPostedTitle;

  /// Under bondNotPostedTitle
  ///
  /// In en, this message translates to:
  /// **'The node has no deposit from the party you chose to slash, so nothing was paid or refunded. Choose another deposit option.'**
  String get bondNotPostedBody;

  /// Result button: back to the confirmation to change the bond choice
  ///
  /// In en, this message translates to:
  /// **'Choose another option'**
  String get bondChooseAgain;

  /// Result: added under a successful resolution that slashed the buyer
  ///
  /// In en, this message translates to:
  /// **'The buyer\'s deposit was slashed.'**
  String get resolvedSlashedBuyer;

  /// Result: added under a successful resolution that slashed the seller
  ///
  /// In en, this message translates to:
  /// **'The seller\'s deposit was slashed.'**
  String get resolvedSlashedSeller;

  /// Result: added under a successful resolution that slashed both
  ///
  /// In en, this message translates to:
  /// **'Both deposits were slashed.'**
  String get resolvedSlashedBoth;

  /// Info row label: which bonds this solver's resolution slashed
  ///
  /// In en, this message translates to:
  /// **'Deposits'**
  String get detailBonds;

  /// Info row label: the order's status when the dispute was opened (active or fiat sent)
  ///
  /// In en, this message translates to:
  /// **'Status before the dispute'**
  String get detailPreviousStatus;

  /// Order status before the dispute: the buyer had not marked the fiat as sent
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get orderStatusActive;

  /// Order status before the dispute: the buyer had marked the fiat as sent
  ///
  /// In en, this message translates to:
  /// **'Fiat sent'**
  String get orderStatusFiatSent;

  /// Disputes tab: the segment of the disputes waiting for a solver
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get disputesPendingSegment;

  /// Disputes tab: the segment of the disputes this key holds
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get myDisputesOpenSegment;

  /// Disputes tab: the segment of the disputes this key held that closed
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get myDisputesClosedSegment;

  /// Screen-reader label of the Pending / In progress / Closed control of the Disputes tab
  ///
  /// In en, this message translates to:
  /// **'Pending, in progress or closed disputes'**
  String get disputesSegmentsLabel;

  /// Disputes, Closed: empty state title
  ///
  /// In en, this message translates to:
  /// **'No closed disputes yet'**
  String get closedEmptyTitle;

  /// Disputes, Closed: empty state explanation
  ///
  /// In en, this message translates to:
  /// **'The disputes you take show up here once they close, whether you resolved them or the parties ended the trade themselves.'**
  String get closedEmptyBody;

  /// How long ago a dispute closed, under a minute
  ///
  /// In en, this message translates to:
  /// **'Closed just now'**
  String get disputeClosedJustNow;

  /// How long ago a dispute closed, in minutes
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Closed 1 minute ago} other{Closed {count} minutes ago}}'**
  String disputeClosedMinutesAgo(int count);

  /// How long ago a dispute closed, in hours
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Closed 1 hour ago} other{Closed {count} hours ago}}'**
  String disputeClosedHoursAgo(int count);

  /// How long ago a dispute closed, in days
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Closed 1 day ago} other{Closed {count} days ago}}'**
  String disputeClosedDaysAgo(int count);

  /// Bottom bar destination: look up any order of the active node by its ID
  ///
  /// In en, this message translates to:
  /// **'Orders'**
  String get navOrders;

  /// Header of the Orders tab
  ///
  /// In en, this message translates to:
  /// **'Look up an order'**
  String get ordersTitle;

  /// Orders tab: what the lookup is for, above the form
  ///
  /// In en, this message translates to:
  /// **'See how this node holds any of its orders right now, in dispute or not. Looking changes nothing.'**
  String get ordersIntro;

  /// Orders tab empty state body before a node is chosen
  ///
  /// In en, this message translates to:
  /// **'Orders are looked up on one Mostro node at a time. Pick the node where you are a solver.'**
  String get ordersNoNodeBody;

  /// Orders tab: placeholder of the order ID field
  ///
  /// In en, this message translates to:
  /// **'Paste the order\'s ID'**
  String get orderIdHint;

  /// Orders tab: the text in the field is not an order ID (a UUID)
  ///
  /// In en, this message translates to:
  /// **'That is not an order ID. One looks like 308e1272-d5f4-47e6-bd97-3504baea9c23.'**
  String get orderIdInvalid;

  /// Orders tab: the primary button that asks the node about the order
  ///
  /// In en, this message translates to:
  /// **'Look up order'**
  String get orderLookupAction;

  /// Orders tab: the node has no order with that ID
  ///
  /// In en, this message translates to:
  /// **'Order not found'**
  String get orderNotFoundTitle;

  /// Orders tab: what to check when the node has no order with that ID
  ///
  /// In en, this message translates to:
  /// **'This node has no order with that ID. Check the ID, and that the order belongs to this node.'**
  String get orderNotFoundBody;

  /// Orders tab: the node did not answer a lookup in time; older nodes do not know the request
  ///
  /// In en, this message translates to:
  /// **'The request or its answer may have been lost, or this node does not answer order lookups yet. Nothing was changed: you can ask again.'**
  String get orderNoAnswerBody;

  /// Orders tab: the node refused the lookup and gave no reason
  ///
  /// In en, this message translates to:
  /// **'It gave no reason. Try again later, or ask the node\'s operator.'**
  String get orderRefusedBody;

  /// Orders tab: the node refused the lookup as an action it does not do (invalid_action)
  ///
  /// In en, this message translates to:
  /// **'This node does not answer order lookups. Its operator may need to update it.'**
  String get orderRefusedUnsupportedBody;

  /// Orders tab: the node refused the lookup because it is rate-limiting this key (too_many_requests)
  ///
  /// In en, this message translates to:
  /// **'The node is getting too many requests. Wait a moment and ask again.'**
  String get orderRefusedBusyBody;

  /// Orders tab: the node refused the lookup with a reason this build has no words for
  ///
  /// In en, this message translates to:
  /// **'It gave a reason this version of Bosstro does not know. Try again later, or ask the node\'s operator.'**
  String get orderRefusedUnknownBody;

  /// Order status: published and waiting, nobody took it yet. The protocol's own word for it, as the solver knows it
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get orderStatusPending;

  /// Order status: the maker has not posted the anti-abuse deposit yet, so the order is not published
  ///
  /// In en, this message translates to:
  /// **'Waiting for the maker\'s deposit'**
  String get orderStatusWaitingMakerDeposit;

  /// Order status: taken, the taker has not posted the anti-abuse deposit yet
  ///
  /// In en, this message translates to:
  /// **'Waiting for the taker\'s deposit'**
  String get orderStatusWaitingTakerDeposit;

  /// Order status: the buyer has not given the invoice to be paid to yet
  ///
  /// In en, this message translates to:
  /// **'Waiting for the buyer\'s invoice'**
  String get orderStatusWaitingBuyerInvoice;

  /// Order status: the seller has not locked the sats yet
  ///
  /// In en, this message translates to:
  /// **'Waiting for the seller to lock the sats'**
  String get orderStatusWaitingPayment;

  /// Order status: taken, under way
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get orderStatusInProgress;

  /// Order status: the seller's sats were taken by the node; the payment to the buyer is under way or failed
  ///
  /// In en, this message translates to:
  /// **'Sats released, buyer not paid yet'**
  String get orderStatusSatsReleased;

  /// Order status: the trade ended, the buyer was paid
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get orderStatusSuccess;

  /// Order status: a party opened a dispute
  ///
  /// In en, this message translates to:
  /// **'In dispute'**
  String get orderStatusDispute;

  /// Order status: cancelled
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get orderStatusCanceled;

  /// Order status: both parties agreed to cancel
  ///
  /// In en, this message translates to:
  /// **'Cancelled by both parties'**
  String get orderStatusCooperativelyCanceled;

  /// Order status: a solver closed the dispute by refunding the seller
  ///
  /// In en, this message translates to:
  /// **'Refunded to the seller by a solver'**
  String get orderStatusRefundedBySolver;

  /// Order status: a solver decided for the buyer; the payment to the buyer is under way or failed
  ///
  /// In en, this message translates to:
  /// **'Decided for the buyer by a solver, not paid yet'**
  String get orderStatusSettledBySolver;

  /// Order status: a solver decided for the buyer and the buyer was paid
  ///
  /// In en, this message translates to:
  /// **'Paid to the buyer by a solver'**
  String get orderStatusPaidBySolver;

  /// Order status: nobody took it in time
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get orderStatusExpired;

  /// Orders, an order: title of the card about the sats the seller locked for the trade
  ///
  /// In en, this message translates to:
  /// **'The seller\'s sats'**
  String get orderFundsTitle;

  /// Orders, an order: label of what the node's Lightning node reports right now, next to what the node's database recorded
  ///
  /// In en, this message translates to:
  /// **'On Lightning now'**
  String get orderOnLightning;

  /// Orders, an order: label of the row that says no sats are locked for this order
  ///
  /// In en, this message translates to:
  /// **'Locked sats'**
  String get orderFundsLocked;

  /// Orders, an order: value of something the order does not have
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get orderValueNone;

  /// Orders, an order: when the node's database says the seller's sats were locked
  ///
  /// In en, this message translates to:
  /// **'Locked (node\'s record)'**
  String get orderFundsHeldAt;

  /// Orders, an order: when the node's database says it collected the seller's sats
  ///
  /// In en, this message translates to:
  /// **'Collected (node\'s record)'**
  String get orderFundsSettledAt;

  /// Seller's sats on Lightning: the seller has not locked them yet
  ///
  /// In en, this message translates to:
  /// **'Not locked yet'**
  String get orderHoldOpen;

  /// Seller's sats on Lightning: locked, still the seller's
  ///
  /// In en, this message translates to:
  /// **'Locked'**
  String get orderHoldAccepted;

  /// Seller's sats on Lightning: the node took them
  ///
  /// In en, this message translates to:
  /// **'Collected by the node'**
  String get orderHoldSettled;

  /// Seller's sats on Lightning: the lock was cancelled, they went back to the seller
  ///
  /// In en, this message translates to:
  /// **'Back with the seller'**
  String get orderHoldCanceled;

  /// Orders, an order: the node's Lightning node has no record of this payment
  ///
  /// In en, this message translates to:
  /// **'No record of it'**
  String get orderLnNotFound;

  /// Orders, an order: the node could not ask its Lightning node (an error, or no answer in time)
  ///
  /// In en, this message translates to:
  /// **'Lightning did not answer'**
  String get orderLnUnavailable;

  /// Orders, an order: a value a newer node sent that this version of the app does not know
  ///
  /// In en, this message translates to:
  /// **'Not known to this version'**
  String get orderValueUnknown;

  /// Orders, an order on a Cashu node: the mint that holds the escrow
  ///
  /// In en, this message translates to:
  /// **'Cashu mint'**
  String get orderCashuMint;

  /// Orders, an order: title of the card about the node's payment to the buyer
  ///
  /// In en, this message translates to:
  /// **'Payment to the buyer'**
  String get orderPayoutTitle;

  /// Orders, an order: label of the row that says no payment to the buyer is under way
  ///
  /// In en, this message translates to:
  /// **'Payment under way'**
  String get orderPayoutUnderWay;

  /// Payment to the buyer on Lightning: sent, not finished
  ///
  /// In en, this message translates to:
  /// **'Under way'**
  String get orderPayoutInFlight;

  /// Payment to the buyer on Lightning: it arrived
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get orderPayoutSucceeded;

  /// Payment to the buyer on Lightning: it failed
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get orderPayoutFailed;

  /// Orders, an order: label of the reason a payment to the buyer failed
  ///
  /// In en, this message translates to:
  /// **'Why it failed'**
  String get orderPayoutWhyFailed;

  /// Why a payment to the buyer failed: it took too long
  ///
  /// In en, this message translates to:
  /// **'Timed out'**
  String get orderPayoutReasonTimeout;

  /// Why a payment to the buyer failed: Lightning found no path to the buyer
  ///
  /// In en, this message translates to:
  /// **'No route to the buyer'**
  String get orderPayoutReasonNoRoute;

  /// Why a payment to the buyer failed: an error of the Lightning node
  ///
  /// In en, this message translates to:
  /// **'Lightning error'**
  String get orderPayoutReasonError;

  /// Why a payment to the buyer failed: the buyer's invoice was wrong or expired
  ///
  /// In en, this message translates to:
  /// **'Wrong payment details'**
  String get orderPayoutReasonDetails;

  /// Why a payment to the buyer failed: the node's Lightning node had too little balance
  ///
  /// In en, this message translates to:
  /// **'Not enough balance on the node'**
  String get orderPayoutReasonBalance;

  /// Why a payment to the buyer failed: it was cancelled
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get orderPayoutReasonCanceled;

  /// Orders, an order: when a payment to the buyer reached its final state
  ///
  /// In en, this message translates to:
  /// **'Ended'**
  String get orderPayoutEndedAt;

  /// Orders, an order: whether the node's last payment to the buyer failed (Yes / No)
  ///
  /// In en, this message translates to:
  /// **'Last payment failed'**
  String get orderPayoutLastFailed;

  /// Orders, an order: how many times the node tried to pay the buyer
  ///
  /// In en, this message translates to:
  /// **'Payment attempts'**
  String get orderPayoutAttempts;

  /// Orders, an order: what Lightning charged to route the payment to the buyer
  ///
  /// In en, this message translates to:
  /// **'Routing fee'**
  String get orderRoutingFee;

  /// Orders, an order: title of the card about the buyer and the seller
  ///
  /// In en, this message translates to:
  /// **'Parties'**
  String get orderPartiesTitle;

  /// Orders, an order: which party opened a dispute (Buyer, Seller, Both, Nobody)
  ///
  /// In en, this message translates to:
  /// **'Dispute opened by'**
  String get orderDisputeOpenedBy;

  /// Orders, an order: which party asked to cancel the trade by agreement (Buyer, Seller, Both, Nobody)
  ///
  /// In en, this message translates to:
  /// **'Cancel asked by'**
  String get orderCancelAskedBy;

  /// Orders, an order: both the buyer and the seller
  ///
  /// In en, this message translates to:
  /// **'Both'**
  String get orderPartyBoth;

  /// Orders, an order: neither the buyer nor the seller
  ///
  /// In en, this message translates to:
  /// **'Nobody'**
  String get orderPartyNobody;

  /// Orders, an order: the order has no anti-abuse deposit
  ///
  /// In en, this message translates to:
  /// **'No deposit on this order'**
  String get orderDepositsNone;

  /// Whose anti-abuse deposit: the party who created the order
  ///
  /// In en, this message translates to:
  /// **'Maker'**
  String get orderBondMaker;

  /// Whose anti-abuse deposit: the party who took the order
  ///
  /// In en, this message translates to:
  /// **'Taker'**
  String get orderBondTaker;

  /// A deposit row of a range order: the part of the maker's deposit slashed for one slice
  ///
  /// In en, this message translates to:
  /// **'Slashed on one slice'**
  String get orderBondSliceSlash;

  /// A deposit row of a range order: what was left of the maker's deposit, returned
  ///
  /// In en, this message translates to:
  /// **'Rest returned to the maker'**
  String get orderBondMakerRefund;

  /// Deposit state: asked for, not posted yet
  ///
  /// In en, this message translates to:
  /// **'Asked for'**
  String get orderBondRequested;

  /// Deposit state: posted and held
  ///
  /// In en, this message translates to:
  /// **'Locked'**
  String get orderBondLocked;

  /// Deposit state: given back
  ///
  /// In en, this message translates to:
  /// **'Returned'**
  String get orderBondReleased;

  /// Deposit state: slashed, its payout to the other party still owed
  ///
  /// In en, this message translates to:
  /// **'Slashed, payout owed'**
  String get orderBondPendingPayout;

  /// Deposit state: slashed and paid to the other party
  ///
  /// In en, this message translates to:
  /// **'Slashed and paid out'**
  String get orderBondSlashed;

  /// Deposit state: slashed, and the other party never claimed it
  ///
  /// In en, this message translates to:
  /// **'Slashed, never claimed'**
  String get orderBondForfeited;

  /// Deposit state: its payout failed
  ///
  /// In en, this message translates to:
  /// **'Payout failed'**
  String get orderBondFailed;

  /// Why a deposit was slashed, after its state: its owner lost the dispute
  ///
  /// In en, this message translates to:
  /// **'lost the dispute'**
  String get orderBondLostDispute;

  /// Why a deposit was slashed, after its state: its owner did not act in time
  ///
  /// In en, this message translates to:
  /// **'did not act in time'**
  String get orderBondTimeout;

  /// Orders, an order: when the order was created
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get orderCreatedAt;

  /// Orders, an order: when the order was taken
  ///
  /// In en, this message translates to:
  /// **'Taken'**
  String get orderTakenAt;

  /// Orders, an order: when the order expires
  ///
  /// In en, this message translates to:
  /// **'Expires'**
  String get orderExpiresAt;

  /// Orders, a range order: the smallest and largest fiat amount it accepts
  ///
  /// In en, this message translates to:
  /// **'Fiat range'**
  String get orderFiatRange;

  /// Orders, an order: the range order this one is a part of
  ///
  /// In en, this message translates to:
  /// **'Part of range order'**
  String get orderRangeParent;

  /// Orders, an order: title of the card about the anti-abuse deposits, with how many rows it has
  ///
  /// In en, this message translates to:
  /// **'Deposits ({count})'**
  String orderDepositsTitle(int count);

  /// A deposit row on a part of a range order: {role} is whose deposit it is (Maker), and it belongs to the whole range order
  ///
  /// In en, this message translates to:
  /// **'{role} (root order)'**
  String orderBondOfRoot(String role);

  /// A range order's fiat range: smallest, largest and the currency code
  ///
  /// In en, this message translates to:
  /// **'{min} – {max} {code}'**
  String orderFiatRangeValue(String min, String max, String code);

  /// Orders, under an order: the time of day the node answered, as the locale writes it
  ///
  /// In en, this message translates to:
  /// **'Asked at {time}'**
  String orderAskedAt(String time);

  /// Push notification, title: a dispute was opened on the solver's node. Shown by Android from android/app/src/main/res/values*/strings.xml (push_dispute_new_title), which a test keeps equal to this
  ///
  /// In en, this message translates to:
  /// **'New dispute'**
  String get pushDisputeNewTitle;

  /// Push notification, body. It names no dispute, node or party: it shows on the lock screen. Android string push_dispute_new_body
  ///
  /// In en, this message translates to:
  /// **'A dispute is waiting for a solver on your node.'**
  String get pushDisputeNewBody;

  /// The name of the notification channel for new disputes, in Android's settings of the app. Android string push_disputes_channel_name
  ///
  /// In en, this message translates to:
  /// **'New disputes'**
  String get pushDisputesChannelName;

  /// Settings row and the title of its screen: notifications of new disputes
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get settingsNotifications;

  /// Settings row value: notifications are turned on
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get notificationsOn;

  /// Settings row value: notifications are turned off
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get notificationsOff;

  /// Notifications screen, the switch: ring when a dispute is opened on the active node
  ///
  /// In en, this message translates to:
  /// **'New disputes on this node'**
  String get notificationsNewDisputes;

  /// Notifications screen, status: the notification server rings this phone for the active node
  ///
  /// In en, this message translates to:
  /// **'Active for this node.'**
  String get notificationsStatusRegistered;

  /// Notifications screen, status: turned on, and there is no active node yet
  ///
  /// In en, this message translates to:
  /// **'Not active yet. Choose a node first.'**
  String get notificationsStatusWaiting;

  /// Notifications screen, status: the notification server refused this phone's token; turning them off and on asks Google for a new one
  ///
  /// In en, this message translates to:
  /// **'The notification server refused this phone. Turn notifications off and on again.'**
  String get notificationsStatusTokenRefused;

  /// Notifications screen, status: the notification server only rings for the nodes on its own list, and the active node is not one
  ///
  /// In en, this message translates to:
  /// **'The notification server does not cover this node, so it will not ring.'**
  String get notificationsStatusNodeNotTrusted;

  /// Notifications screen, status: the notification server answered 'too many requests'; the app retries
  ///
  /// In en, this message translates to:
  /// **'The notification server asked to wait. Bosstro will try again by itself.'**
  String get notificationsStatusRateLimited;

  /// Notifications screen, status: the notification server failed or there is no connection; the app retries
  ///
  /// In en, this message translates to:
  /// **'The notification server could not be reached. Bosstro will try again by itself.'**
  String get notificationsStatusServerUnavailable;

  /// Notifications screen, what a notification is. It carries no content: the dispute is read from the relays when the app opens
  ///
  /// In en, this message translates to:
  /// **'Your phone rings when a dispute is opened on your node, even with Bosstro closed. The notification does not say which dispute: open Bosstro to see it.'**
  String get notificationsAbout;

  /// Notifications screen, what is shared with whom when notifications are on
  ///
  /// In en, this message translates to:
  /// **'Google delivers the notification. The notification server sees your IP address and which node you follow, never your key.'**
  String get notificationsPrivacy;

  /// Notifications screen: Android shows the notification in the system's language, not the one chosen in the app
  ///
  /// In en, this message translates to:
  /// **'The notification is shown in your phone\'s language.'**
  String get notificationsLanguageNote;

  /// Dialog title: the OS refused the permission to show notifications
  ///
  /// In en, this message translates to:
  /// **'Notifications are blocked'**
  String get notificationsBlockedTitle;

  /// Dialog body: how to allow notifications after refusing them
  ///
  /// In en, this message translates to:
  /// **'Allow notifications for Bosstro in your phone\'s settings, then turn them on here again.'**
  String get notificationsBlockedBody;

  /// Dialog title: Google gave no device token
  ///
  /// In en, this message translates to:
  /// **'Notifications are not available'**
  String get notificationsUnavailableTitle;

  /// Dialog body: why no token came, and what to check
  ///
  /// In en, this message translates to:
  /// **'They need Google Play Services and an internet connection. Check both and try again.'**
  String get notificationsUnavailableBody;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>[
    'de',
    'en',
    'es',
    'fr',
    'it',
    'nl',
    'pt',
  ].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'fr':
      return AppLocalizationsFr();
    case 'it':
      return AppLocalizationsIt();
    case 'nl':
      return AppLocalizationsNl();
    case 'pt':
      return AppLocalizationsPt();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
