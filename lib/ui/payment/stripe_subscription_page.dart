// @dart=2.9

import 'dart:async';

import 'package:ente_auth/ente_theme_data.dart';
import 'package:ente_auth/models/billing_plan.dart';
import 'package:ente_auth/models/subscription.dart';
import 'package:ente_auth/models/user_details.dart';
import 'package:ente_auth/services/billing_service.dart';
import 'package:ente_auth/services/user_service.dart';
import 'package:ente_auth/ui/common/bottom_shadow.dart';
import 'package:ente_auth/ui/common/dialogs.dart';
import 'package:ente_auth/ui/common/loading_widget.dart';
import 'package:ente_auth/ui/common/progress_dialog.dart';
import 'package:ente_auth/ui/common/web_page.dart';
import 'package:ente_auth/ui/payment/child_subscription_widget.dart';
import 'package:ente_auth/ui/payment/payment_web_page.dart';
import 'package:ente_auth/ui/payment/skip_subscription_widget.dart';
import 'package:ente_auth/ui/payment/subscription_common_widgets.dart';
import 'package:ente_auth/ui/payment/subscription_plan_widget.dart';
import 'package:ente_auth/utils/dialog_util.dart';
import 'package:ente_auth/utils/toast_util.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:step_progress_indicator/step_progress_indicator.dart';
import 'package:url_launcher/url_launcher_string.dart';

class StripeSubscriptionPage extends StatefulWidget {
  final bool isOnboarding;

  const StripeSubscriptionPage({
    this.isOnboarding = false,
    Key key,
  }) : super(key: key);

  @override
  State<StripeSubscriptionPage> createState() => _StripeSubscriptionPageState();
}

class _StripeSubscriptionPageState extends State<StripeSubscriptionPage> {
  final _logger = Logger("StripeSubscriptionPage");
  final _billingService = BillingService.instance;
  final _userService = UserService.instance;
  Subscription _currentSubscription;
  ProgressDialog _dialog;
  UserDetails _userDetails;

  // indicates if user's subscription plan is still active
  bool _hasActiveSubscription;
  FreePlan _freePlan;
  List<BillingPlan> _plans = [];
  bool _hasLoadedData = false;
  bool _isLoading = false;
  bool _isStripeSubscriber = false;
  bool _showYearlyPlan = false;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _fetchSub() async {
    return _userService
        .getUserDetailsV2(memoryCount: false)
        .then((userDetails) async {
      _userDetails = userDetails;
      _currentSubscription = userDetails.subscription;
      _showYearlyPlan = _currentSubscription.isYearlyPlan();
      _hasActiveSubscription = _currentSubscription.isValid();
      _isStripeSubscriber = _currentSubscription.paymentProvider == stripe;
      return _filterStripeForUI().then((value) {
        _hasLoadedData = true;
        setState(() {});
      });
    });
  }

  // _filterPlansForUI is used for initializing initState & plan toggle states
  Future<void> _filterStripeForUI() async {
    final billingPlans = await _billingService.getBillingPlans();
    _freePlan = billingPlans.freePlan;
    _plans = billingPlans.plans.where((plan) {
      if (plan.stripeID == null || plan.stripeID.isEmpty) {
        return false;
      }
      final isYearlyPlan = plan.period == 'year';
      return isYearlyPlan == _showYearlyPlan;
    }).toList();
    setState(() {});
  }

  FutureOr onWebPaymentGoBack(dynamic value) async {
    // refresh subscription
    await _dialog.show();
    try {
      await _fetchSub();
    } catch (e) {
      showToast(context, "Failed to refresh subscription");
    }
    await _dialog.hide();

    // verify user has subscribed before redirecting to main page
    if (widget.isOnboarding &&
        _currentSubscription != null &&
        _currentSubscription.isValid() &&
        _currentSubscription.productID != freeProductID) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appBar = PreferredSize(
      preferredSize: const Size(double.infinity, 60),
      child: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).backgroundColor,
              blurRadius: 16,
              offset: const Offset(0, 8),
            )
          ],
        ),
        child: widget.isOnboarding
            ? AppBar(
                elevation: 0,
                title: Hero(
                  tag: "subscription",
                  child: StepProgressIndicator(
                    totalSteps: 4,
                    currentStep: 4,
                    selectedColor:
                        Theme.of(context).colorScheme.alternativeColor,
                    roundedEdges: const Radius.circular(10),
                    unselectedColor: Theme.of(context)
                        .colorScheme
                        .stepProgressUnselectedColor,
                  ),
                ),
              )
            : AppBar(
                elevation: 0,
                title: const Text("Subscription"),
              ),
      ),
    );
    return Scaffold(
      appBar: appBar,
      body: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          _getBody(),
          const BottomShadowWidget(
            offsetDy: 40,
          )
        ],
      ),
    );
  }

  Widget _getBody() {
    if (!_isLoading) {
      _isLoading = true;
      _dialog = createProgressDialog(context, "Please wait...");
      _fetchSub();
    }
    if (_hasLoadedData) {
      if (_userDetails.isPartOfFamily() && !_userDetails.isFamilyAdmin()) {
        return ChildSubscriptionWidget(userDetails: _userDetails);
      } else {
        return _buildPlans();
      }
    }
    return const EnteLoadingWidget();
  }

  Widget _buildPlans() {
    final widgets = <Widget>[];

    widgets.add(
      SubscriptionHeaderWidget(
        isOnboarding: widget.isOnboarding,
        currentUsage: _userDetails.getFamilyOrPersonalUsage(),
      ),
    );

    widgets.addAll([
      Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: _getStripePlanWidgets(),
      ),
      const Padding(padding: EdgeInsets.all(4)),
    ]);

    widgets.add(_showSubscriptionToggle());

    if (_hasActiveSubscription) {
      widgets.add(ValidityWidget(currentSubscription: _currentSubscription));
    }

    if (_currentSubscription.productID == freeProductID) {
      if (widget.isOnboarding) {
        widgets.add(SkipSubscriptionWidget(freePlan: _freePlan));
      }
      widgets.add(const SubFaqWidget());
    }

    // only active subscription can be renewed/canceled
    if (_hasActiveSubscription && _isStripeSubscriber) {
      widgets.add(_stripeRenewOrCancelButton());
    }

    if (_currentSubscription.productID != freeProductID) {
      widgets.addAll([
        Align(
          alignment: Alignment.center,
          child: GestureDetector(
            onTap: () async {
              final String paymentProvider =
                  _currentSubscription.paymentProvider;
              switch (_currentSubscription.paymentProvider) {
                case stripe:
                  await _launchStripePortal();
                  break;
                case playStore:
                  launchUrlString(
                    "https://play.google.com/store/account/subscriptions?sku=" +
                        _currentSubscription.productID +
                        "&package=io.ente.authenticator",
                  );
                  break;
                case appStore:
                  launchUrlString("https://apps.apple.com/account/billing");
                  break;
                default:
                  final String capitalizedWord = paymentProvider.isNotEmpty
                      ? '${paymentProvider[0].toUpperCase()}${paymentProvider.substring(1).toLowerCase()}'
                      : '';
                  showErrorDialog(
                    context,
                    "Sorry",
                    "Please contact us at support@ente.io to manage your "
                        "$capitalizedWord subscription.",
                  );
              }
            },
            child: Container(
              padding: const EdgeInsets.fromLTRB(40, 80, 40, 20),
              child: Column(
                children: [
                  RichText(
                    text: TextSpan(
                      text: "Payment details",
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontFamily: 'Inter-Medium',
                        fontSize: 14,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ]);
    }

    if (!widget.isOnboarding) {
      widgets.addAll([
        Align(
          alignment: Alignment.topCenter,
          child: GestureDetector(
            onTap: () async {
              await _launchFamilyPortal();
            },
            child: Container(
              padding: const EdgeInsets.fromLTRB(40, 0, 40, 80),
              child: Column(
                children: [
                  RichText(
                    text: TextSpan(
                      text: "Manage family",
                      style: Theme.of(context).textTheme.overline,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ]);
    }

    return SingleChildScrollView(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: widgets,
      ),
    );
  }

  Future<void> _launchStripePortal() async {
    await _dialog.show();
    try {
      final String url = await _billingService.getStripeCustomerPortalUrl();
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (BuildContext context) {
            return WebPage("Payment details", url);
          },
        ),
      ).then((value) => onWebPaymentGoBack);
    } catch (e) {
      await _dialog.hide();
      showGenericErrorDialog(context);
    }
    await _dialog.hide();
  }

  Future<void> _launchFamilyPortal() async {
    if (_userDetails.subscription.productID == freeProductID) {
      await showErrorDialog(
        context,
        "Now you can share your storage plan with your family members!",
        "Customers on paid plans can add up to 5 family members without paying extra. Each member gets their own private space.",
      );
      return;
    }
    await _dialog.show();
    try {
      final String jwtToken = await _userService.getFamiliesToken();
      final bool familyExist = _userDetails.isPartOfFamily();
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (BuildContext context) {
            return WebPage(
              "Family",
              '$kFamilyPlanManagementUrl?token=$jwtToken&isFamilyCreated=$familyExist',
            );
          },
        ),
      ).then((value) => onWebPaymentGoBack);
    } catch (e) {
      await _dialog.hide();
      showGenericErrorDialog(context);
    }
    await _dialog.hide();
  }

  Widget _stripeRenewOrCancelButton() {
    final bool isRenewCancelled =
        _currentSubscription.attributes?.isCancelled ?? false;
    final String title =
        isRenewCancelled ? "Renew subscription" : "Cancel subscription";
    return TextButton(
      child: Text(
        title,
        style: TextStyle(
          color: (isRenewCancelled
                  ? Colors.greenAccent
                  : Theme.of(context).colorScheme.onSurface)
              .withOpacity(isRenewCancelled ? 1.0 : 0.2),
        ),
      ),
      onPressed: () async {
        bool confirmAction = false;
        if (isRenewCancelled) {
          final choice = await showChoiceDialog(
            context,
            title,
            "Are you sure you want to renew?",
            firstAction: "No",
            secondAction: "Yes",
          );
          confirmAction = choice == DialogUserChoice.secondChoice;
        } else {
          final choice = await showChoiceDialog(
            context,
            title,
            'Are you sure you want to cancel?',
            firstAction: 'Yes, cancel',
            secondAction: 'No',
            actionType: ActionType.critical,
          );
          confirmAction = choice == DialogUserChoice.firstChoice;
        }
        if (confirmAction) {
          toggleStripeSubscription(isRenewCancelled);
        }
      },
    );
  }

  Future<void> toggleStripeSubscription(bool isRenewCancelled) async {
    await _dialog.show();
    try {
      isRenewCancelled
          ? await _billingService.activateStripeSubscription()
          : await _billingService.cancelStripeSubscription();
      await _fetchSub();
    } catch (e) {
      showToast(
        context,
        isRenewCancelled ? 'failed to renew' : 'failed to cancel',
      );
    }
    await _dialog.hide();
  }

  List<Widget> _getStripePlanWidgets() {
    final List<Widget> planWidgets = [];
    bool foundActivePlan = false;
    for (final plan in _plans) {
      final productID = plan.stripeID;
      if (productID == null || productID.isEmpty) {
        continue;
      }
      final isActive =
          _hasActiveSubscription && _currentSubscription.productID == productID;
      if (isActive) {
        foundActivePlan = true;
      }
      planWidgets.add(
        Material(
          child: InkWell(
            onTap: () async {
              if (isActive) {
                return;
              }
              // prompt user to cancel their active subscription form other
              // payment providers
              if (!_isStripeSubscriber &&
                  _hasActiveSubscription &&
                  _currentSubscription.productID != freeProductID) {
                showErrorDialog(
                  context,
                  "Sorry",
                  "Please cancel your existing subscription from "
                      "${_currentSubscription.paymentProvider} first",
                );
                return;
              }
              if (_userDetails.getFamilyOrPersonalUsage() > plan.storage) {
                showErrorDialog(
                  context,
                  "Sorry",
                  "You cannot downgrade to this plan",
                );
                return;
              }
              String stripPurChaseAction = 'buy';
              if (_isStripeSubscriber && _hasActiveSubscription) {
                // confirm if user wants to change plan or not
                final result = await showChoiceDialog(
                  context,
                  "Confirm plan change",
                  "Are you sure you want to change your plan?",
                  firstAction: "No",
                  secondAction: 'Yes',
                );
                if (result != DialogUserChoice.secondChoice) {
                  return;
                }
                stripPurChaseAction = 'update';
              }
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (BuildContext context) {
                    return PaymentWebPage(
                      planId: plan.stripeID,
                      actionType: stripPurChaseAction,
                    );
                  },
                ),
              ).then((value) => onWebPaymentGoBack(value));
            },
            child: SubscriptionPlanWidget(
              storage: plan.storage,
              price: plan.price,
              period: plan.period,
              isActive: isActive,
            ),
          ),
        ),
      );
    }
    if (!foundActivePlan && _hasActiveSubscription) {
      _addCurrentPlanWidget(planWidgets);
    }
    return planWidgets;
  }

  Widget _showSubscriptionToggle() {
    Widget _planText(String title, bool reduceOpacity) {
      return Padding(
        padding: const EdgeInsets.only(left: 4, right: 4),
        child: Text(
          title,
          style: TextStyle(
            color: Theme.of(context)
                .colorScheme
                .onSurface
                .withOpacity(reduceOpacity ? 0.5 : 1.0),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.only(left: 8, right: 8, top: 4, bottom: 4),
      margin: const EdgeInsets.only(bottom: 12),
      // color: Color.fromRGBO(10, 40, 40, 0.3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _planText("Monthly", _showYearlyPlan),
          Switch(
            value: _showYearlyPlan,
            activeColor: Colors.white,
            inactiveThumbColor: Colors.white,
            onChanged: (value) async {
              _showYearlyPlan = value;
              await _filterStripeForUI();
            },
          ),
          _planText("Yearly", !_showYearlyPlan)
        ],
      ),
    );
  }

  void _addCurrentPlanWidget(List<Widget> planWidgets) {
    // don't add current plan if it's monthly plan but UI is showing yearly plans
    // and vice versa.
    if (_showYearlyPlan != _currentSubscription.isYearlyPlan() &&
        _currentSubscription.productID != freeProductID) {
      return;
    }
    int activePlanIndex = 0;
    for (; activePlanIndex < _plans.length; activePlanIndex++) {
      if (_plans[activePlanIndex].storage > _currentSubscription.storage) {
        break;
      }
    }
    planWidgets.insert(
      activePlanIndex,
      Material(
        child: InkWell(
          onTap: () {},
          child: SubscriptionPlanWidget(
            storage: _currentSubscription.storage,
            price: _currentSubscription.price,
            period: _currentSubscription.period,
            isActive: true,
          ),
        ),
      ),
    );
  }
}