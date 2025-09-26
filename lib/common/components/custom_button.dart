import 'package:flutter/material.dart';

class CustomButton extends StatefulWidget {
  final String buttonText;
  final VoidCallback onTap;
  final Color initialColor;
  final Color pressedColor;

  const CustomButton({
    Key? key,
    required this.buttonText,
    required this.onTap,
    required this.initialColor,
    required this.pressedColor,
  }) : super(key: key);

  @override
  _CustomButtonState createState() => _CustomButtonState();
}

class _CustomButtonState extends State<CustomButton> {
  late Color buttonColor;

  @override
  void initState() {
    super.initState();
    buttonColor = widget.initialColor; // Set initial color
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap, // Trigger the provided callback
      onTapDown: (_) {
        // Change to pressed color when finger is down
        setState(() {
          buttonColor = widget.pressedColor;
        });
      },
      onTapUp: (_) {
        // Revert to initial color when finger is lifted
        setState(() {
          buttonColor = widget.initialColor;
        });
      },
      onTapCancel: () {
        // Revert to initial color if tap is cancelled
        setState(() {
          buttonColor = widget.initialColor;
        });
      },
      child: Container(
        decoration: BoxDecoration(
          color: buttonColor,
          borderRadius: BorderRadius.circular(16),
        ),
        height: 60,
        width: 300,
        alignment: Alignment.center,
        child: Text(
          widget.buttonText,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
