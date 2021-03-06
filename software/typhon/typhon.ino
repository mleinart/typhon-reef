/*
Typhon firmware
N. Enders, R. Ensminger

Dependencies:
 LiquidCrystal
 Wire
 EEPROMVar
 Button
 Time
 DS1307RTC
*/

// include the libraries:
#include <LiquidCrystal.h>
#include <Wire.h>
#include <Button.h>
#include <EEPROMVar.h>
#include <Time.h>
#include <DS1307RTC.h>


/*** DEFINES ***/
// LCD config
#define LCD_RS 8        // RS pin
#define LCD_ENABLE 7    // enable pin
#define LCD_DATA4 9     // d4 pin
#define LCD_DATA5 4     // d5 pin
#define LCD_DATA6 16    // d6 pin
#define LCD_DATA7 2     // d7 pin
#define LCD_BACKLIGHT 6 // backlight pin

// Backlight config
#define BACKLIGHT_DIM 10              // PWM value for backlight at idle
#define BACKLIGHT_ON 70               // PWM value for backlight when on
#define BACKLIGHT_IDLE_MS 10000 // Backlight idle delay

/**** Define Variables & Constants ****/
/**************************************/
// Create the LCD
LiquidCrystal lcd(LCD_RS, LCD_ENABLE, LCD_DATA4, LCD_DATA5, LCD_DATA6, LCD_DATA7);

// Set up backlight
unsigned long backlightIdleMs = 0;  // counter since backlight turned on

// create the menu counter
int menuCount   = 1;
int menuSelect = 0;

//create the plus and minus navigation delay counter with its initial maximum of 250.
byte btnMinDelay = 25;
byte btnMaxDelay = 200;

byte btnMaxIteration = 5;
byte btnCurrIteration;

//create manual override variables
boolean override = false;
byte overmenu = 0;
int overpercent = 0;

// create the buttons
Button menu     = Button(12,PULLDOWN);
Button select   = Button(13,PULLDOWN);
Button plus     = Button(14,PULLDOWN);
Button minus    = Button(15,PULLDOWN);

// LED variables. These control the behavior of lighting. Change these to customize behavoir
int minCounter = 0;         // counter that resets at midnight.
int oldMinCounter = 0;      // counter that resets at midnight.
int oneLed = 9;             // pin for channel 1
int twoLed = 10;            // pin for channel 2
int threeLed = 11;          // pin for channel 3
int fourLed = 3;            // pin for channel 4

int oneVal = 0;             // current value for channel 1
int twoVal = 0;             // current value for channel 2
int threeVal = 0;           // current value for channel 3
int fourVal = 0;            // current value for channel 4

// Variables making use of EEPROM memory:

EEPROMVar<int> oneStartMins = 750;     // minute to start this channel.
EEPROMVar<int> onePhotoPeriod = 720;   // photoperiod in minutes for this channel.
EEPROMVar<int> oneMax = 100;           // max intensity for this channel, as a percentage
EEPROMVar<int> oneFadeDuration = 60;   // duration of the fade on and off for sunrise and sunset for
                                       //    this channel.
EEPROMVar<int> twoStartMins = 810;
EEPROMVar<int> twoPhotoPeriod = 600;
EEPROMVar<int> twoMax = 100;
EEPROMVar<int> twoFadeDuration = 60;

EEPROMVar<int> threeStartMins = 810;
EEPROMVar<int> threePhotoPeriod = 600;
EEPROMVar<int> threeMax = 100;
EEPROMVar<int> threeFadeDuration = 60;

EEPROMVar<int> fourStartMins = 480;
EEPROMVar<int> fourPhotoPeriod = 510;
EEPROMVar<int> fourMax = 100;
EEPROMVar<int> fourFadeDuration = 60;

// variables to invert the output PWM signal,
// for use with drivers that consider 0 to be "on"
// i.e. buckpucks. If you need to provide an inverted
// signal on any channel, set the appropriate variable to true.
boolean oneInverted = false;
boolean twoInverted = false;
boolean threeInverted = false;
boolean fourInverted = false;

/*
int oneStartMins = 1380;      // minute to start this channel.
int onePhotoPeriod = 120;   // photoperiod in minutes for this channel.
int oneMax = 100;           // max intensity for this channel, as a percentage
int oneFadeDuration = 60;   // duration of the fade on and off for sunrise and sunset for
                            //    this channel.
int twoStartMins = 800;
int twoPhotoPeriod = 60;
int twoMax = 100;
int twoFadeDuration = 15;

int threeStartMins = 800;
int threePhotoPeriod = 60;
int threeMax = 100;
int threeFadeDuration = 30;

int fourStartMins = 800;
int fourPhotoPeriod = 120;
int fourMax = 100;
int fourFadeDuration = 60;
*/

/****** LED Functions ******/
/***************************/
//function to set LED brightness according to time of day
//function has three equal phases - ramp up, hold, and ramp down

int   setLed(int mins,         // current time in minutes
            int ledPin,        // pin for this channel of LEDs
            int start,         // start time for this channel of LEDs
            int period,        // photoperiod for this channel of LEDs
            int fade,          // fade duration for this channel of LEDs
            int ledMax,        // max value for this channel
            boolean inverted   // true if the channel is inverted
            )  {
  int val = 0;

      //fade up
      if (mins > start || mins <= start + fade)  {
        val = map(mins - start, 0, fade, 0, ledMax);
      }
      //fade down
      if (mins > start + period - fade && mins <= start + period)  {
        val = map(mins - (start + period - fade), 0, fade, ledMax, 0);
      }
      //off or post-midnight run.
      if (mins <= start || mins > start + period)  {
        if((start+period)%1440 < start && (start + period)%1440 > mins )
          {
            val=map((start+period-mins)%1440,0,fade,0,ledMax);
          }
        else
        val = 0;
      }


    if (val > ledMax)  {val = ledMax;}
    if (val < 0) {val = 0; }

  if (inverted) {analogWrite(ledPin, map(val, 0, 100, 255, 0));}
  else {analogWrite(ledPin, map(val, 0, 100, 0, 255));}
  if(override){val=overpercent;}
  return val;
}

/**** Display Functions ****/
/***************************/

//button hold function
int btnCurrDelay(byte curr)
{
  if(curr==btnMaxIteration)
  {
    btnCurrIteration = btnMaxIteration;
    return btnMaxDelay;
  }
  else if(btnCurrIteration ==0)
  {
    return btnMinDelay;
  }
  else
  {
    btnCurrIteration--;
    return btnMaxDelay;
  }
}

// format a number of minutes into a readable time (24 hr format)
void printMins(int mins,       //time in minutes to print
               boolean ampm    //print am/pm?
              )  {
  int hr = (mins%1440)/60;
  int mn = mins%60;
    if(hr<10){
      lcd.print(" ");
    }
    lcd.print(hr);
    lcd.print(":");
    if(mn<10){
      lcd.print("0");
    }
    lcd.print(mn);
}

// format hours, mins, secs into a readable time (24 hr format)
void printHMS (byte hr,
               byte mn,
               byte sec      //time to print
              )
{

    if(hr<10){
      lcd.print(" ");
    }
    lcd.print(hr, DEC);
    lcd.print(":");
    if(mn<10){
      lcd.print("0");
    }
    lcd.print(mn, DEC);
    lcd.print(":");
    if(sec<10){
      lcd.print("0");
    }
    lcd.print(sec, DEC);
}
void ovrSetAll(int pct){
    analogWrite(oneLed,map(pct,0,100,0,255));
    analogWrite(twoLed,map(pct,0,100,0,255));
    analogWrite(threeLed,map(pct,0,100,0,255));
    analogWrite(fourLed,map(pct,0,100,0,255));
}

/**** Setup ****/
/***************/

void setup() {
  // Initialize clock
  setSyncProvider(RTC.get);
  // XXX Error to check battery if RTC isnt initialized
  Wire.begin();
  pinMode(LCD_BACKLIGHT, OUTPUT);
  lcd.begin(16, 2);
  digitalWrite(LCD_BACKLIGHT, HIGH);
  lcd.print("Typhon-Reef");
  lcd.setCursor(0,1);
  lcd.print("");
  delay(5000);
  lcd.clear();
  analogWrite(LCD_BACKLIGHT, BACKLIGHT_DIM);
  btnCurrIteration = btnMaxIteration;
}

/***** Loop *****/
/****************/

void loop() {
  oldMinCounter = minCounter;
  minCounter = hour() * 60 + minute();

  //reset plus & minus acceleration counters if the button's state has changed
  if(plus.stateChanged())
  {
   btnCurrDelay(btnMaxIteration);
  }
  if(minus.stateChanged())
  {
    btnCurrDelay(btnMaxIteration);
  }


  //check & set fade durations
  if(oneFadeDuration > onePhotoPeriod/2 && onePhotoPeriod >0){oneFadeDuration = onePhotoPeriod/2;}
  if(oneFadeDuration<1){oneFadeDuration=1;}

  if(twoFadeDuration > twoPhotoPeriod/2 && twoPhotoPeriod >0){twoFadeDuration = twoPhotoPeriod/2;}
  if(twoFadeDuration<1){twoFadeDuration=1;}

  if(threeFadeDuration > threePhotoPeriod/2 && threePhotoPeriod >0){threeFadeDuration = threePhotoPeriod/2;}
  if(threeFadeDuration<1){threeFadeDuration=1;}

  if(fourFadeDuration > fourPhotoPeriod/2 && fourPhotoPeriod > 0){fourFadeDuration = fourPhotoPeriod/2;}
  if(fourFadeDuration<1){fourFadeDuration=1;}

  //check & set any time functions


  //set outputs
  if(!override){
  oneVal = setLed(minCounter, oneLed, oneStartMins, onePhotoPeriod, oneFadeDuration, oneMax, oneInverted);
  twoVal = setLed(minCounter, twoLed, twoStartMins, twoPhotoPeriod, twoFadeDuration, twoMax, twoInverted);
  threeVal = setLed(minCounter, threeLed, threeStartMins, threePhotoPeriod, threeFadeDuration, threeMax, threeInverted);
  fourVal = setLed(minCounter, fourLed, fourStartMins, fourPhotoPeriod, fourFadeDuration, fourMax, fourInverted);
  }
  else{
    ovrSetAll(overpercent);
  }


  //turn the backlight off and reset the menu if the idle time has elapsed
  if(backlightIdleMs + BACKLIGHT_IDLE_MS < millis() && backlightIdleMs > 0 ){
    analogWrite(LCD_BACKLIGHT, BACKLIGHT_DIM);
    menuCount = 1;
    lcd.clear();
    backlightIdleMs = 0;
  }

  //iterate through the menus
  if(menu.uniquePress()){
    analogWrite(LCD_BACKLIGHT, BACKLIGHT_ON);
    backlightIdleMs = millis();
    if(menuCount < 20){
      menuCount++;
    }else {
      menuCount = 1;
    }
  lcd.clear();
  }
  if(menuCount == 1){
    //main screen turn on!!!
    if (minCounter > oldMinCounter){
      lcd.clear();
    }
    lcd.setCursor(0,0);
    printHMS(hour(), minute(), second());
    lcd.setCursor(0,1);
    lcd.print(oneVal);
    lcd.setCursor(4,1);
    lcd.print(twoVal);
    lcd.setCursor(8,1);
    lcd.print(threeVal);
    lcd.setCursor(12,1);
    lcd.print(fourVal);
  }

  if(menuCount == 2){
    //Manual Override Menu
    lcd.setCursor(0,0);
    lcd.print("Manual Overrides");
    lcd.setCursor(0,1);
    lcd.print("All: ");
    if(select.uniquePress()){
      if(menuSelect < 3){menuSelect++;}
      else{menuSelect = 0;}
      backlightIdleMs = millis();
    }

    if(menuSelect == 0){
      lcd.print("Timer");
      override = false;}
    if(menuSelect == 1){
      lcd.print("ON   ");
      overpercent = 100;
      override = true;}
    if(menuSelect == 2){
      lcd.print("OFF  ");
      overpercent = 0;
      override = true;}
    if(menuSelect == 3){
      override = true;
      lcd.print(overpercent,DEC);
      lcd.print("%  ");
      if(plus.isPressed() && overpercent <100)
        {
          overpercent++;
          delay(btnCurrDelay(btnCurrIteration-1));
          backlightIdleMs = millis();
        }

        if(minus.isPressed() && overpercent > 0)
        {
          overpercent--;
          delay(btnCurrDelay(btnCurrIteration-1));
          backlightIdleMs = millis();
        }
      }
}



  if(menuCount == 3){
    //set start time for channel one
    lcd.setCursor(0,0);
    lcd.print("Channel 1 Start");
    lcd.setCursor(0,1);
    printMins(oneStartMins, true);

    if(plus.isPressed() && oneStartMins < 1440){
        oneStartMins++;
        if(onePhotoPeriod >0){onePhotoPeriod--;}
        else{onePhotoPeriod=1439;}
      delay(btnCurrDelay(btnCurrIteration-1));
      backlightIdleMs = millis();
    }
    if(minus.isPressed() && oneStartMins > 0){
        oneStartMins--;
        if(onePhotoPeriod<1439){onePhotoPeriod++;}
        else{onePhotoPeriod=0;}
      delay(btnCurrDelay(btnCurrIteration-1));
      backlightIdleMs = millis();
    }
  }

  if(menuCount == 4){
    //set end time for channel one
    lcd.setCursor(0,0);
    lcd.print("Channel 1 End");
    lcd.setCursor(0,1);
    printMins(oneStartMins+onePhotoPeriod, true);
    if(plus.isPressed()){
      if(onePhotoPeriod < 1439){
      onePhotoPeriod++;}
      else{
        onePhotoPeriod=0;
      }
      delay(btnCurrDelay(btnCurrIteration-1));
      backlightIdleMs = millis();
    }
    if(minus.isPressed()){
      if(onePhotoPeriod >0){
        onePhotoPeriod--;}
      else{
        onePhotoPeriod=1439;
      }
      delay(btnCurrDelay(btnCurrIteration-1));
      backlightIdleMs = millis();
    }
  }

  if(menuCount == 5){
    //set fade duration for channel one
    lcd.setCursor(0,0);
    lcd.print("Channel 1 Fade");
    lcd.setCursor(0,1);
    printMins(oneFadeDuration, false);
    if(plus.isPressed() && (oneFadeDuration < onePhotoPeriod/2 || oneFadeDuration == 0)){
      oneFadeDuration++;
      delay(btnCurrDelay(btnCurrIteration-1));
      backlightIdleMs = millis();
    }
    if(minus.isPressed() && oneFadeDuration > 1){
      oneFadeDuration--;
      delay(btnCurrDelay(btnCurrIteration-1));
      backlightIdleMs = millis();
    }
  }

  if(menuCount == 6){
    //set intensity for channel one
    lcd.setCursor(0,0);
    lcd.print("Channel 1 Max");
    lcd.setCursor(1,1);
    lcd.print(oneMax);
    lcd.print("  ");
    if(plus.isPressed() && oneMax < 100){
      oneMax++;
      delay(btnCurrDelay(btnCurrIteration-1));
      backlightIdleMs = millis();
    }
    if(minus.isPressed() && oneMax > 0){
      oneMax--;
      delay(btnCurrDelay(btnCurrIteration-1));
      backlightIdleMs = millis();
    }
  }

  if(menuCount == 7){
    //set start time for channel two
    lcd.setCursor(0,0);
    lcd.print("Channel 2 Start");
    lcd.setCursor(0,1);
    printMins(twoStartMins, true);
    if(plus.isPressed() && twoStartMins < 1440){
        twoStartMins++;
        if(twoPhotoPeriod >0){twoPhotoPeriod--;}
        else{twoPhotoPeriod=1439;}
      delay(btnCurrDelay(btnCurrIteration-1));
      backlightIdleMs = millis();
    }
    if(minus.isPressed() && twoStartMins > 0){
        twoStartMins--;
        if(twoPhotoPeriod<1439){twoPhotoPeriod++;}
        else{twoPhotoPeriod=0;}
      delay(btnCurrDelay(btnCurrIteration-1));
      backlightIdleMs = millis();
    }
  }

  if(menuCount == 8){
    //set end time for channel two
    lcd.setCursor(0,0);
    lcd.print("Channel 2 End");
    lcd.setCursor(0,1);
    printMins(twoStartMins+twoPhotoPeriod, true);
    if(plus.isPressed()){
      if(twoPhotoPeriod < 1439){
      twoPhotoPeriod++;}
      else{
        twoPhotoPeriod=0;
      }
      delay(btnCurrDelay(btnCurrIteration-1));
      backlightIdleMs = millis();
    }
    if(minus.isPressed()){
      if(twoPhotoPeriod >0){
        twoPhotoPeriod--;}
      else{
        twoPhotoPeriod=1439;
      }
      delay(btnCurrDelay(btnCurrIteration-1));
      backlightIdleMs = millis();
    }
  }

  if(menuCount == 9){
    //set fade duration for channel two
    lcd.setCursor(0,0);
    lcd.print("Channel 2 Fade");
    lcd.setCursor(0,1);
    printMins(twoFadeDuration, false);
    if(plus.isPressed() && (twoFadeDuration < twoPhotoPeriod/2 || twoFadeDuration == 0)){
      twoFadeDuration++;
      delay(btnCurrDelay(btnCurrIteration-1));
      backlightIdleMs = millis();
    }
    if(minus.isPressed() && twoFadeDuration > 1){
      twoFadeDuration--;
      delay(btnCurrDelay(btnCurrIteration-1));
      backlightIdleMs = millis();
    }
  }

  if(menuCount == 10){
    //set intensity for channel two
    lcd.setCursor(0,0);
    lcd.print("Channel 2 Max");
    lcd.setCursor(1,1);
    lcd.print(twoMax);
    lcd.print("  ");
    if(plus.isPressed() && twoMax < 100){
      twoMax++;
      delay(btnCurrDelay(btnCurrIteration-1));
      backlightIdleMs = millis();
    }
    if(minus.isPressed() && twoMax > 0){
      twoMax--;
      delay(btnCurrDelay(btnCurrIteration-1));
      backlightIdleMs = millis();
    }
  }

  if(menuCount == 11){
    //set start time for channel three
    lcd.setCursor(0,0);
    lcd.print("Channel 3 Start");
    lcd.setCursor(0,1);
    printMins(threeStartMins, true);
    if(plus.isPressed() && threeStartMins < 1440){
        threeStartMins++;
        if(threePhotoPeriod >0){threePhotoPeriod--;}
        else{threePhotoPeriod=1439;}
        delay(btnCurrDelay(btnCurrIteration-1));
      backlightIdleMs = millis();
    }
    if(minus.isPressed() && threeStartMins > 0){
        threeStartMins--;
        if(threePhotoPeriod<1439){threePhotoPeriod++;}
        else{threePhotoPeriod=0;}
        delay(btnCurrDelay(btnCurrIteration-1));
      backlightIdleMs = millis();
    }
  }

  if(menuCount == 12){
    //set end time for channel three
    lcd.setCursor(0,0);
    lcd.print("Channel 3 End");
    lcd.setCursor(0,1);
    printMins(threeStartMins+threePhotoPeriod, true);
    if(plus.isPressed()){
      if(threePhotoPeriod < 1439){
      threePhotoPeriod++;}
      else{
        threePhotoPeriod=0;
      }
      delay(btnCurrDelay(btnCurrIteration-1));
      backlightIdleMs = millis();
    }
    if(minus.isPressed()){
      if(threePhotoPeriod >0){
        threePhotoPeriod--;}
      else{
        threePhotoPeriod=1439;
      }
      delay(btnCurrDelay(btnCurrIteration-1));
      backlightIdleMs = millis();
    }
  }

  if(menuCount == 13){
    //set fade duration for channel three
    lcd.setCursor(0,0);
    lcd.print("Channel 3 Fade");
    lcd.setCursor(0,1);
    printMins(threeFadeDuration, false);
    if(plus.isPressed() && (threeFadeDuration < threePhotoPeriod/2 || threeFadeDuration == 0)){
      threeFadeDuration++;
      delay(btnCurrDelay(btnCurrIteration-1));
      backlightIdleMs = millis();
    }
    if(minus.isPressed() && threeFadeDuration > 1){
      threeFadeDuration--;
      delay(btnCurrDelay(btnCurrIteration-1));
      backlightIdleMs = millis();
    }
  }

  if(menuCount == 14){
    //set intensity for channel three
    lcd.setCursor(0,0);
    lcd.print("Channel 3 Max");
    lcd.setCursor(1,1);
    lcd.print(threeMax);
    lcd.print("  ");
    if(plus.isPressed() && threeMax < 100){
      threeMax++;
      delay(btnCurrDelay(btnCurrIteration-1));
      backlightIdleMs = millis();
    }
    if(minus.isPressed() && threeMax > 0){
      threeMax--;
      delay(btnCurrDelay(btnCurrIteration-1));
      backlightIdleMs = millis();
    }
  }

  if(menuCount == 15){
    //set start time for channel four
    lcd.setCursor(0,0);
    lcd.print("Channel 4 Start");
    lcd.setCursor(0,1);
    printMins(fourStartMins, true);
    if(plus.isPressed() && fourStartMins < 1440){
        fourStartMins++;
        if(fourPhotoPeriod >0){fourPhotoPeriod--;}
        else{fourPhotoPeriod=1439;}
        delay(btnCurrDelay(btnCurrIteration-1));
      backlightIdleMs = millis();
    }
    if(minus.isPressed() && fourStartMins > 0){
        fourStartMins--;
        if(fourPhotoPeriod<1439){fourPhotoPeriod++;}
        else{fourPhotoPeriod=0;}
      delay(btnCurrDelay(btnCurrIteration-1));
      backlightIdleMs = millis();
    }
  }

  if(menuCount == 16){
    //set end time for channel four
    lcd.setCursor(0,0);
    lcd.print("Channel 4 End");
    lcd.setCursor(0,1);
    printMins(fourStartMins+fourPhotoPeriod, true);
    if(plus.isPressed()){
      if(fourPhotoPeriod < 1439){
      fourPhotoPeriod++;}
      else{
        fourPhotoPeriod=0;
      }
      delay(btnCurrDelay(btnCurrIteration-1));
      backlightIdleMs = millis();
    }
    if(minus.isPressed()){
      if(fourPhotoPeriod >0){
        fourPhotoPeriod--;}
      else{
        fourPhotoPeriod=1439;
      }
      delay(btnCurrDelay(btnCurrIteration-1));
      backlightIdleMs = millis();
    }
  }

  if(menuCount == 17){
    //set fade duration for channel four
    lcd.setCursor(0,0);
    lcd.print("Channel 4 Fade");
    lcd.setCursor(0,1);
    printMins(fourFadeDuration, false);
    if(plus.isPressed() && (fourFadeDuration < fourPhotoPeriod/2 || fourFadeDuration == 0)){
      fourFadeDuration++;
      delay(btnCurrDelay(btnCurrIteration-1));
      backlightIdleMs = millis();
    }
    if(minus.isPressed() && fourFadeDuration > 1){
      fourFadeDuration--;
      delay(btnCurrDelay(btnCurrIteration-1));
      backlightIdleMs = millis();
    }
  }

  if(menuCount == 18){
    //set intensity for channel four
    lcd.setCursor(0,0);
    lcd.print("Channel 4 Max");
    lcd.setCursor(1,1);
    lcd.print(fourMax);
    lcd.print("   ");
    if(plus.isPressed() && fourMax < 100){
      fourMax++;
      delay(btnCurrDelay(btnCurrIteration-1));
      backlightIdleMs = millis();
    }
    if(minus.isPressed() && fourMax > 0){
      fourMax--;
      delay(btnCurrDelay(btnCurrIteration-1));
      backlightIdleMs = millis();
    }
  }

  if(menuCount == 19){
    //set hours
    lcd.setCursor(0,0);
    lcd.print("Set Time: Hrs");
    lcd.setCursor(0,1);
    printHMS(hour(), minute(), second());
    if(plus.isPressed()){
      adjustTime(SECS_PER_HOUR);
      delay(btnCurrDelay(btnCurrIteration-1));
      backlightIdleMs = millis();
    }
    if(minus.isPressed()){
      adjustTime(-SECS_PER_HOUR);
      delay(btnCurrDelay(btnCurrIteration-1));
      backlightIdleMs = millis();
    }
  }

  if(menuCount == 20){
    //set minutes
    lcd.setCursor(0,0);
    lcd.print("Set Time: Mins");
    lcd.setCursor(0,1);
    printHMS(hour(), minute(), second());
    if(plus.isPressed()){
      adjustTime(SECS_PER_MIN);
      delay(btnCurrDelay(btnCurrIteration-1));
      backlightIdleMs = millis();
    }
    if(minus.isPressed()){
      adjustTime(-SECS_PER_MIN);
      delay(btnCurrDelay(btnCurrIteration-1));
      backlightIdleMs = millis();
    }
  }
}
