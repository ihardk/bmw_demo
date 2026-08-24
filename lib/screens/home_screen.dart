import 'package:bmw_demo/constants/my_images.dart';
import 'package:bmw_demo/constants/my_textstyle.dart';
import 'package:bmw_demo/screens/counter/events_screen.dart';
import 'package:bmw_demo/screens/fan_screen.dart';
import 'package:bmw_demo/utils/sound_pool_singleton.dart';
import 'package:bmw_demo/widgets/background_container.dart';
import 'package:bmw_demo/widgets/lable_and_value_widget.dart';
import 'package:bmw_demo/widgets/my_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../constants/my_colors.dart';
import '../constants/my_font_icons.dart';
import '../widgets/my_polygon_button.dart';
import 'common_ui.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BackgroundContainer(
        child: SafeArea(
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned(
                left: -90,
                child: _bBuildLeftColumn(isRight: false),
              ),
              Positioned(
                right: -90,
                child: _bBuildRightColumn(),
              ),
              Align(
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    bTopText(),
                    bI4Image(),
                    const SizedBox(height: 30),
                    _buildBWMimage(),
                    const SizedBox(height: 30),
                    _buildRange(),
                    const SizedBox(height: 30),
                    _buildPercentage(),
                    const SizedBox(height: 30),
                    _buildTemprature(),
                    const SizedBox(height: 60),
                  ],
                ),
              ),
              _bBuildSettingsButton(context),
              _bBuildCountersButton(context),
              _bBMWbutton(),
            ],
          ),
        ),
      ),
    );
  }

  _bBuildLeftColumn({bool isRight = true}) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 30),
        MyNewPolygonButton(
          sides: 6,
          icon: MyFontIcons.car,
          isLeft: !isRight,
        ),
        const SizedBox(height: 5),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isRight) const SizedBox(width: 30),
            MyNewPolygonButton(
              isLeft: !isRight,
              icon: MyFontIcons.airlineSeat,
            ),
            if (isRight) const SizedBox(width: 30),
          ],
        ),
        const SizedBox(height: 5),
        MyNewPolygonButton(
          sides: 6,
          isLeft: !isRight,
          icon: MyFontIcons.fan,
        ),
        const SizedBox(height: 30),
      ],
    );
  }

  _bBuildRightColumn({bool isRight = true}) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 30),
        MyNewPolygonButton(
          sides: 6,
          isLeft: !isRight,
          icon: MyFontIcons.icq,
        ),
        const SizedBox(height: 5),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isRight) const SizedBox(width: 30),
            MyNewPolygonButton(
              isLeft: !isRight,
              icon: MyFontIcons.location,
            ),
            if (isRight) const SizedBox(width: 30),
          ],
        ),
        const SizedBox(height: 5),
        MyNewPolygonButton(
          sides: 6,
          isLeft: !isRight,
          icon: MyFontIcons.stopwatch,
        ),
        const SizedBox(height: 30),
      ],
    );
  }

  Widget _buildBWMimage() {
    return Visibility.maintain(
      visible: true,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Image.asset(
          kIi4front,
          width: 140,
        ),
      ),
    ).animate().scale(duration: const Duration(seconds: 1));
  }

  Positioned _bBMWbutton() {
    return Positioned(
      bottom: 40,
      left: 0,
      right: 0,
      child: Column(
        children: [
          const BMWbutton(),
          const SizedBox(height: 20),
          Text(
            "Start Engine",
            style: ktBody.copyWith(
              fontSize: 12,
              color: kcSecondaryStart,
            ),
          )
        ],
      ),
    );
  }

  _bBuildCountersButton(BuildContext context) {
    return Positioned(
      top: 20,
      left: 10,
      child: MyRoundButton(
        icon: const Icon(Icons.hourglass_bottom_rounded),
        onPressed: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (context) => const EventsScreen(),
          ));
        },
      ),
    );
  }

  _bBuildSettingsButton(BuildContext context) {
    return Positioned(
      top: 20,
      right: 10,
      child: MyRoundButton(
        icon: const Icon(MyFontIcons.cog),
        onPressed: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (context) => const FanScreen(),
          ));
        },
      ),
    );
  }

  _buildTemprature() {
    return const TextValueWidget(label: "Temprature", value: "26° C");
  }

  _buildPercentage() {
    return const TextValueWidget(
        label: "Battery", value: "60%", valueTextStyle: ktHeading1);
  }

  _buildRange() {
    return const TextValueWidget(label: "Range", value: "260 KM");
  }
}

class BMWbutton extends StatefulWidget {
  const BMWbutton({
    super.key,
  });

  @override
  State<BMWbutton> createState() => _BMWbuttonState();
}

class _BMWbuttonState extends State<BMWbutton> {
  //
  bool isPlaying = false;

  @override
  void initState() {
    SoundPoolSingleton.instance
        .loadSound(soundAsset: "sounds/bmw_long.mp3");
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return MyRoundButton(
      height: 105,
      width: 105,
      gradeintColors: const [
        kcSecondaryStart,
        kcSecondaryStart,
        kcSecondaryEnd
      ],
      image: Image.asset(
        kIBMWLogo,
        height: 40,
        width: 40,
      ),
      onPressed: () {
        if (isPlaying) {
          SoundPoolSingleton.instance.stopSound();
        } else {
          SoundPoolSingleton.instance.playSound();
        }
        setState(() {
          isPlaying = !isPlaying;
        });
      },
    );
  }
}
