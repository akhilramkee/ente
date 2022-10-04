// @dart=2.9

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:photos/core/configuration.dart';
import 'package:photos/services/feature_flag_service.dart';
import 'package:photos/ui/settings/account_section_widget.dart';
import 'package:photos/ui/settings/app_version_widget.dart';
import 'package:photos/ui/settings/backup_section_widget.dart';
import 'package:photos/ui/settings/danger_section_widget.dart';
import 'package:photos/ui/settings/debug_section_widget.dart';
import 'package:photos/ui/settings/details_section_widget.dart';
import 'package:photos/ui/settings/info_section_widget.dart';
import 'package:photos/ui/settings/security_section_widget.dart';
import 'package:photos/ui/settings/social_section_widget.dart';
import 'package:photos/ui/settings/support_section_widget.dart';
import 'package:photos/ui/settings/theme_switch_widget.dart';

class SettingsPage extends StatelessWidget {
  final ValueNotifier<String> emailNotifier;
  const SettingsPage({Key key, @required this.emailNotifier}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _getBody(context),
    );
  }

  Widget _getBody(BuildContext context) {
    final hasLoggedIn = Configuration.instance.getToken() != null;
    final List<Widget> contents = [];
    contents.add(
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: AnimatedBuilder(
            // [AnimatedBuilder] accepts any [Listenable] subtype.
            animation: emailNotifier,
            builder: (BuildContext context, Widget child) {
              return Text(
                emailNotifier.value,
                style: Theme.of(context)
                    .textTheme
                    .subtitle1
                    .copyWith(overflow: TextOverflow.ellipsis),
              );
            },
          ),
        ),
      ),
    );
    const sectionSpacing = SizedBox(
      height: 8,
    );
    contents.add(const Padding(padding: EdgeInsets.all(4)));
    if (hasLoggedIn) {
      contents.addAll([
        const DetailsSectionWidget(),
        const Padding(padding: EdgeInsets.only(bottom: 24)),
        // MenuItemWidget(
        //   captionedTextWidget: CaptionedTextWidget(
        //     text: "Button",
        //     subText: "Sub text",
        //   ),
        //   isHeaderOfExpansion: false,
        //   trailingSwitch: ToggleSwitch(
        //     value: true,
        //     onChanged: () {},
        //   ),
        // ),
        const BackupSectionWidget(),
        sectionSpacing,
        const AccountSectionWidget(),
        sectionSpacing,
      ]);
    }
    contents.addAll([
      const SecuritySectionWidget(),
      sectionSpacing,
    ]);

    if (Platform.isAndroid || kDebugMode) {
      contents.addAll([
        const ThemeSwitchWidget(),
        sectionSpacing,
      ]);
    }

    contents.addAll([
      const SupportSectionWidget(),
      sectionSpacing,
      const SocialSectionWidget(),
      sectionSpacing,
      const InfoSectionWidget(),
    ]);
    if (hasLoggedIn) {
      contents.addAll([
        sectionSpacing,
        const DangerSectionWidget(),
      ]);
    }

    if (FeatureFlagService.instance.isInternalUserOrDebugBuild() &&
        hasLoggedIn) {
      contents.addAll([sectionSpacing, const DebugSectionWidget()]);
    }
    contents.add(const AppVersionWidget());
    contents.add(
      const Padding(
        padding: EdgeInsets.only(bottom: 60),
      ),
    );

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 350),
            child: Column(
              children: contents,
            ),
          ),
        ),
      ),
    );
  }
}
