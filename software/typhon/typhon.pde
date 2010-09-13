/*
// Typhon firmware
// v0.1 alpha 2010-08-06
// N. Enders
//
// This sketch provides firmware for the Typhon LED controller.
// It provides a structure to fade 4 independent channels of LED lighting
// on and off each day, to simulate sunrise and sunset.
//
// Current work in progress:
// - store all LED variables in EEPROM so they are not reset by a loss of power
//
// Future developments may include:
// - moon phase simulation
// - storm simulation
// 
// Sketch developed in Arduino-18
// Requires LiquidCrystal, Wire, EEPROM, EEPROMVar, and Button libraries.
// Button is available here: http://www.arduino.cc/playground/Code/Button
// EEPROMVar is available here: http://www.arduino.cc/playground/uploads/Profiles/EEPROMVar_01.zip
*/

// include the libraries:
#include <LiquidCrystal.h>
#include "Wire.h"
#include <Button.h>
#include <EEPROM.h>
#include <EEPROMVar.h>


/**** Define Variables & Constants ****/
/**************************************/

// set the RTC's I2C address
#define DS1307_I2C_ADDRESS 0x68
// create the LCD
LiquidCrystal lcd(8, 7, 5, 4, 16, 2);
// set up backlight
int bkl         = 6;        // backlight pin
byte bklIdle    = 10;       // PWM value for backlight at idle
byte bklOn      = 70;       // PWM value for backlight when on
int bklDelay    = 10000;    // ms for the backlight to idle before turning off
unsigned long bklTime = 0;  // counter since backlight turned on
// create the menu counter
int menuCount   = 1;
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

EEPROMVar<int> oneStartMins(480);      // minute to start this channel.
EEPROMVar<int> onePhotoPeriod = 510;   // photoperiod in minutes for this channel.
EEPROMVar<int> oneMax = 100;           // max intensity for this channel, as a percentage
EEPROMVar<int> oneFadeDuration = 60;   // duration of the fade on and off for sunrise and sunset for
                                       //    this channel.
EEPROMVar<int> twoStartMins = 480;
EEPROMVar<int> twoPhotoPeriod = 510;
EEPROMVar<int> twoMax = 100;
EEPROMVar<int> twoFadeDuration = 60;

EEPROMVar<int> threeStartMins = 480;
EEPROMVar<int> threePhotoPeriod = 510;
EEPROMVar<int> threeMax = 100;
EEPROMVar<int> threeFadeDuration = 60;
                            
EEPROMVar<int> fourStartMins = 480;
EEPROMVar<int> fourPhotoPeriod = 510;  
EEPROMVar<int> fourMax = 100;          
EEPROMVar<int> fourFadeDuration = 60;  




/****** RTC Functions ******/
/***************************/

// Convert decimal numbers to binary coded decimal
byte decToBcd(byte val)
{
  return ( (val/10*16) + (val%10) );
}

// Convert binary coded decimal to decimal numbers
byte bcdToDec(byte val)
{
  return ( (val/16*10) + (val%16) );
}

// Sets date and time, starts the clock
void setDate(byte second,        // 0-59
             byte minute,        // 0-59
             byte hour,          // 1-23
             byte dayOfWeek,     // 1-7
             byte dayOfMonth,    // 1-31
             byte month,         // 1-12
             byte year)          // 0-99
{
   Wire.beginTransmission(DS1307_I2C_ADDRESS);
   Wire.send(0);
   Wire.send(decToBcd(second));
   Wire.send(decToBcd(minute));
   Wire.send(decToBcd(hour));
   Wire.send(decToBcd(dayOfWeek));
   Wire.send(decToBcd(dayOfMonth));
   Wire.send(decToBcd(month));
   Wire.send(decToBcd(year));
   Wire.endTransmission();
}

// Gets the date and time
void getDate(byte *second,
             byte *minute,
             byte *hour,
             byte *dayOfWeek,
             byte *dayOfMonth,
             byte *month,
             byte *year)
{
  Wire.beginTransmission(DS1307_I2C_ADDRESS);
  Wire.send(0);
  Wire.endTransmission();
  Wire.requestFrom(DS1307_I2C_ADDRESS, 7);
  *second     = bcdToDec(Wire.receive() & 0x7f);
  *minute     = bcdToDec(Wire.receive());
  *hour       = bcdToDec(Wire.receive() & 0x3f);
  *dayOfWeek  = bcdToDec(Wire.receive());
  *dayOfMonth = bcdToDec(Wire.receive());
  *month      = bcdToDec(Wire.receive());
  *year       = bcdToDec(Wire.receive());
}

/****** LED Functions ******/
/***************************/
//function to set LED brightness according to time of day
//function has three equal phases - ramp up, hold, and ramp down
int   setLed(int mins,    // current time in minutes
            int ledPin,  // pin for this channel of LEDs
            int start,   // start time for this channel of LEDs
            int period,  // photoperiod for this channel of LEDs
            int fade,    // fade duration for this channel of LEDs
            int ledMax   // max value for this channel
            )  {
  int val = 0;
  if (mins <= start || mins > start + period)  {
    val = 0;
  }
  if (mins > start && mins <= start + fade)  {
    val = map(mins - start, 0, fade, 0, ledMax);
  }
  if (mins > start + fade && mins <= start + period - fade)  {
    val = ledMax;
  }
  if (mins > start + period - fade && mins <= start + period)  {
    val = map(mins - (start + period - fade), 0, fade, ledMax, 0);
  }
  analogWrite(ledPin, map(val, 0, 100, 0, 255));
  return val;
}

/**** Display Functions ****/
/***************************/

// format a number of minutes into a readable time
void printMins(int mins,       //time in minutes to print
               boolean ampm    //print am/pm?
              )  {
  int hr = mins/60;
  int mn = mins%60;
  if(hr<13){
    if(hr<10){
      lcd.print(" ");
    }
    lcd.print(hr);
    lcd.print(":");
    if(mn<10){
      lcd.print("0");
    }
    lcd.print(mn);
    if(ampm){
      lcd.print(" AM");
    }
  } else {
    if(hr<22){
      lcd.print(" ");
    }
    lcd.print(hr-12);
    lcd.print(":");
    if(mn<10){
      lcd.print("0");
    }
    lcd.print(mn);
    if(ampm){
      lcd.print(" PM");
    }
  }
}

// format hours, mins, secs into a readable time
void printHMS (byte hr,
               byte mn,
               byte sec      //time to print
              )  {
  if(hr<13){
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
    lcd.print(" AM");
  } else {
    if(hr<22){
      lcd.print(" ");
    }
    lcd.print(hr-12, DEC);
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
    lcd.print(" PM");
  }
}

/**** Setup ****/
/***************/

void setup() {
  Wire.begin();
  pinMode(bkl, OUTPUT);
  lcd.begin(16, 2);
  digitalWrite(bkl, HIGH);
  lcd.print("This is Typhon!!!");
  lcd.setCursor(0,1);
  lcd.print("");
  delay(1000);
  lcd.clear();
  //setDate(1, 15, 11, 5, 5, 8, 10);
  analogWrite(bkl,bklIdle);
}

/***** Loop *****/
/****************/

void loop() {
  byte second, minute, hour, dayOfWeek, dayOfMonth, month, year;
  getDate(&second, &minute, &hour, &dayOfWeek, &dayOfMonth, &month, &year);
  oldMinCounter = minCounter;
  minCounter = hour * 60 + minute;

  //set outputs
  oneVal = setLed(minCounter, oneLed, oneStartMins, onePhotoPeriod, oneFadeDuration, oneMax);
  twoVal = setLed(minCounter, twoLed, twoStartMins, twoPhotoPeriod, twoFadeDuration, twoMax);
  threeVal = setLed(minCounter, threeLed, threeStartMins, threePhotoPeriod, threeFadeDuration, threeMax);
  fourVal = setLed(minCounter, fourLed, fourStartMins, fourPhotoPeriod, fourFadeDuration, fourMax);
  
  //turn the backlight off and reset the menu if the idle time has elapsed
  if(bklTime + bklDelay < millis() && bklTime > 0 ){
    analogWrite(bkl,bklIdle);
    menuCount = 1;
    lcd.clear();
    bklTime = 0;
  }

  //iterate through the menus
  if(menu.uniquePress()){
    analogWrite(bkl,bklOn);
    bklTime = millis();
    if(menuCount < 19){
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
    printHMS(hour, minute, second);
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
    //set start time for channel one
    lcd.setCursor(0,0);
    lcd.print("Channel 1 Start");
    lcd.setCursor(0,1);
    printMins(oneStartMins, true);
    if(plus.uniquePress() && oneStartMins < 1440){
      oneStartMins++;
    }
    if(minus.uniquePress() && oneStartMins > 0){
      oneStartMins--;
    }
  }

  if(menuCount == 3){
    //set end time for channel one
    lcd.setCursor(0,0);
    lcd.print("Channel 1 End");
    lcd.setCursor(0,1);
    printMins(oneStartMins+onePhotoPeriod, true);
    if(plus.uniquePress() && onePhotoPeriod < 1440 - oneStartMins){
      onePhotoPeriod++;
    }
    if(minus.uniquePress() && onePhotoPeriod > 0){
      onePhotoPeriod--;
    }
  }

  if(menuCount == 4){
    //set fade duration for channel one
    lcd.setCursor(0,0);
    lcd.print("Channel 1 Fade");
    lcd.setCursor(0,1);
    printMins(oneFadeDuration, false);
    if(plus.uniquePress() && oneFadeDuration > onePhotoPeriod/2){
      oneFadeDuration++;
    }
    if(minus.uniquePress() && oneFadeDuration > 0){
      oneFadeDuration--;
    }
  }

  if(menuCount == 5){
    //set intensity for channel one
    lcd.setCursor(0,0);
    lcd.print("Channel 1 Max");
    lcd.setCursor(1,1);
    lcd.print(oneMax);
    if(plus.uniquePress() && oneMax < 100){
      lcd.clear();
      oneMax++;
    }
    if(minus.uniquePress() && oneMax > 0){
      lcd.clear();
      oneMax--;
    }
  }

  if(menuCount == 6){
    //set start time for channel two
    lcd.setCursor(0,0);
    lcd.print("Channel 2 Start");
    lcd.setCursor(0,1);
    printMins(twoStartMins, true);
    if(plus.uniquePress() && twoStartMins < 1440){
      twoStartMins++;
    }
    if(minus.uniquePress() && twoStartMins > 0){
      twoStartMins--;
    }
  }

  if(menuCount == 7){
    //set end time for channel two
    lcd.setCursor(0,0);
    lcd.print("Channel 2 End");
    lcd.setCursor(0,1);
    printMins(twoStartMins+twoPhotoPeriod, true);
    if(plus.uniquePress() && twoPhotoPeriod < 1440 - twoStartMins){
      twoPhotoPeriod++;
    }
    if(minus.uniquePress() && twoPhotoPeriod > 0){
      twoPhotoPeriod--;
    }
  }

  if(menuCount == 8){
    //set fade duration for channel two
    lcd.setCursor(0,0);
    lcd.print("Channel 2 Fade");
    lcd.setCursor(0,1);
    printMins(twoFadeDuration, false);
    if(plus.uniquePress() && twoFadeDuration > twoPhotoPeriod/2){
      twoFadeDuration++;
    }
    if(minus.uniquePress() && twoFadeDuration > 0){
      twoFadeDuration--;
    }
  }

  if(menuCount == 9){
    //set intensity for channel two
    lcd.setCursor(0,0);
    lcd.print("Channel 2 Max");
    lcd.setCursor(1,1);
    lcd.print(twoMax);
    if(plus.uniquePress() && twoMax < 100){
      lcd.clear();
      twoMax++;
    }
    if(minus.uniquePress() && twoMax > 0){
      lcd.clear();
      twoMax--;
    }
  }

  if(menuCount == 10){
    //set start time for channel three
    lcd.setCursor(0,0);
    lcd.print("Channel 3 Start");
    lcd.setCursor(0,1);
    printMins(threeStartMins, true);
    if(plus.uniquePress() && threeStartMins < 1440){
      threeStartMins++;
    }
    if(minus.uniquePress() && threeStartMins > 0){
      threeStartMins--;
    }
  }

  if(menuCount == 11){
    //set end time for channel three
    lcd.setCursor(0,0);
    lcd.print("Channel 3 End");
    lcd.setCursor(0,1);
    printMins(threeStartMins+threePhotoPeriod, true);
    if(plus.uniquePress() && threePhotoPeriod < 1440 - threeStartMins){
      threePhotoPeriod++;
    }
    if(minus.uniquePress() && threePhotoPeriod > 0){
      threePhotoPeriod--;
    }
  }

  if(menuCount == 12){
    //set fade duration for channel three
    lcd.setCursor(0,0);
    lcd.print("Channel 3 Fade");
    lcd.setCursor(0,1);
    printMins(threeFadeDuration, false);
    if(plus.uniquePress() && threeFadeDuration > threePhotoPeriod/2){
      threeFadeDuration++;
    }
    if(minus.uniquePress() && threeFadeDuration > 0){
      threeFadeDuration--;
    }
  }

  if(menuCount == 13){
    //set intensity for channel three
    lcd.setCursor(0,0);
    lcd.print("Channel 3 Max");
    lcd.setCursor(1,1);
    lcd.print(threeMax);
    if(plus.uniquePress() && threeMax < 100){
      lcd.clear();
      threeMax++;
    }
    if(minus.uniquePress() && threeMax > 0){
      lcd.clear();
      threeMax--;
    }
  }

  if(menuCount == 14){
    //set start time for channel four
    lcd.setCursor(0,0);
    lcd.print("Channel 4 Start");
    lcd.setCursor(0,1);
    printMins(fourStartMins, true);
    if(plus.uniquePress() && fourStartMins < 1440){
      fourStartMins++;
    }
    if(minus.uniquePress() && fourStartMins > 0){
      fourStartMins--;
    }
  }

  if(menuCount == 15){
    //set end time for channel four
    lcd.setCursor(0,0);
    lcd.print("Channel 4 End");
    lcd.setCursor(0,1);
    printMins(fourStartMins+fourPhotoPeriod, true);
    if(plus.uniquePress() && fourPhotoPeriod < 1440 - fourStartMins){
      fourPhotoPeriod++;
    }
    if(minus.uniquePress() && fourPhotoPeriod > 0){
      fourPhotoPeriod--;
    }
  }

  if(menuCount == 16){
    //set fade duration for channel four
    lcd.setCursor(0,0);
    lcd.print("Channel 4 Fade");
    lcd.setCursor(0,1);
    printMins(fourFadeDuration, false);
    if(plus.uniquePress() && fourFadeDuration > fourPhotoPeriod/2){
      fourFadeDuration++;
    }
    if(minus.uniquePress() && fourFadeDuration > 0){
      fourFadeDuration--;
    }
  }

  if(menuCount == 17){
    //set intensity for channel four
    lcd.setCursor(0,0);
    lcd.print("Channel 4 Max");
    lcd.setCursor(1,1);
    lcd.print(fourMax);
    if(plus.uniquePress() && fourMax < 100){
      lcd.clear();
      fourMax++;
    }
    if(minus.uniquePress() && fourMax > 0){
      lcd.clear();
      fourMax--;
    }
  }

  if(menuCount == 18){
    //set hours
    lcd.setCursor(0,0);
    lcd.print("Set Time: Hrs");
    lcd.setCursor(0,1);
    printHMS(hour, minute, second);
    if(plus.uniquePress() && hour < 23){
      hour++;
    }
    if(minus.uniquePress() && hour > 0){
      hour--;
    }
  setDate(second, minute, hour, dayOfWeek, dayOfMonth, month, year);
  }
  
  if(menuCount == 19){
    //set minutes
    lcd.setCursor(0,0);
    lcd.print("Set Time: Mins");
    lcd.setCursor(0,1);
    printHMS(hour, minute, second);
    if(plus.uniquePress() && minute < 59){
      minute++;
    }
    if(minus.uniquePress() && minute > 0){
      minute--;
    }
  setDate(second, minute, hour, dayOfWeek, dayOfMonth, month, year);
  }
}

