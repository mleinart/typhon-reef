/*
// Typhon firmware
// v0.2 alpha 2010-14-09
// N. Enders, R. Ensminger
//
// This sketch provides firmware for the Typhon LED controller.
// It provides a structure to fade 4 independent channels of LED lighting
// on and off each day, to simulate sunrise and sunset.
// Modified November 9, 2010 R.Ensminger to add Manual Override on/off.
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
#include <Wire.h>
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
int menuSelect = 0;
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
/*
EEPROMVar<int> oneStartMins = 60;      // minute to start this channel.
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
*/

int oneStartMins = 750;      // minute to start this channel.
//int onePhotoPeriod = 920;
int onePhotoPeriod = 720;   // photoperiod in minutes for this channel.
int oneMax = 100;           // max intensity for this channel, as a percentage
int oneFadeDuration = 60;   // duration of the fade on and off for sunrise and sunset for
                                       //    this channel.                                    
int twoStartMins = 810;
int twoPhotoPeriod = 600;
int twoMax = 100;
int twoFadeDuration = 60;

int threeStartMins = 810;
int threePhotoPeriod = 600;
int threeMax = 100;
int threeFadeDuration = 60;
                            
int fourStartMins = 480;
int fourPhotoPeriod = 510;  
int fourMax = 0;          
int fourFadeDuration = 60;  
/*

int oneStartMins = 1320;      // minute to start this channel.
int onePhotoPeriod = 240;   // photoperiod in minutes for this channel.
int oneMax = 100;           // max intensity for this channel, as a percentage
int oneFadeDuration = 119;   // duration of the fade on and off for sunrise and sunset for
                                       //    this channel.

*/
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

////$$$$$$$$$$$$$
//needs some modification to keep it from shutting off right at midnight, consider using something other than current time in minutes.

int   setLed(int mins,    // current time in minutes
            int ledPin,  // pin for this channel of LEDs
            int start,   // start time for this channel of LEDs
            int period,  // photoperiod for this channel of LEDs
            int fade,    // fade duration for this channel of LEDs
            int ledMax   // max value for this channel
            )  {
  int val = 0;
  
    
    
// Post-shutoff turns right back on @ 100%.

    
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
    
  analogWrite(ledPin, map(val, 0, 100, 0, 255));
  if(override){val=overpercent;}
  return val;
}

/**** Display Functions ****/
/***************************/

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
  Wire.begin();
  pinMode(bkl, OUTPUT);
  lcd.begin(16, 2);
  digitalWrite(bkl, HIGH);
  lcd.print("Typhon-Reef");
  lcd.setCursor(0,1);
  lcd.print("");
  delay(5000);
  lcd.clear();
  //setDate(1, 20, 20, 2, 8, 11, 10);
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
  if(!override){
  oneVal = setLed(minCounter, oneLed, oneStartMins, onePhotoPeriod, oneFadeDuration, oneMax);
  twoVal = setLed(minCounter, twoLed, twoStartMins, twoPhotoPeriod, twoFadeDuration, twoMax);
  threeVal = setLed(minCounter, threeLed, threeStartMins, threePhotoPeriod, threeFadeDuration, threeMax);
  fourVal = setLed(minCounter, fourLed, fourStartMins, fourPhotoPeriod, fourFadeDuration, fourMax);
  }
  else{
    ovrSetAll(overpercent);
  }
  
  
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
    printHMS(hour, minute, second);
    //lcd.print(" ");
    //lcd.print(minCounter);
    
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
      bklTime = millis();
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
        if(plus.uniquePress() && overpercent <100){
          overpercent++;
          bklTime = millis();}
        if(minus.uniquePress() && overpercent > 0){
          overpercent--;
          bklTime = millis();}
      }
  }


  if(menuCount == 3){
    //set start time for channel one
    lcd.setCursor(0,0);
    lcd.print("Channel 1 Start");
    lcd.setCursor(0,1);
    printMins(oneStartMins, true);
    if(plus.uniquePress() && oneStartMins < 1440){
      oneStartMins++;
      bklTime = millis();
    }
    if(minus.uniquePress() && oneStartMins > 0){
      oneStartMins--;
      bklTime = millis();
    }
  }

  if(menuCount == 4){
    //set end time for channel one
    lcd.setCursor(0,0);
    lcd.print("Channel 1 End");
    lcd.setCursor(0,1);
    printMins(oneStartMins+onePhotoPeriod, true);
    if(plus.uniquePress() && onePhotoPeriod < 1440){
      onePhotoPeriod++;
      bklTime = millis();
    }
    if(minus.uniquePress() && onePhotoPeriod > 0){
      onePhotoPeriod--;
      bklTime = millis();
    }
  }

///////////////////////////////////////////////////////////////////// WORK ON FADE DURATION & over Midnight!
  if(menuCount == 5){
    //set fade duration for channel one
    lcd.setCursor(0,0);
    lcd.print("Channel 1 Fade");
    lcd.setCursor(0,1);
    printMins(oneFadeDuration, false);
    if(plus.uniquePress() && oneFadeDuration > oneFadeDuration/2){
      oneFadeDuration++;
      bklTime = millis();
    }
    if(minus.uniquePress()){
      oneFadeDuration--;
      bklTime = millis();
    }
  }

  if(menuCount == 6){
    //set intensity for channel one
    lcd.setCursor(0,0);
    lcd.print("Channel 1 Max");
    lcd.setCursor(1,1);
    lcd.print(oneMax);
    if(plus.uniquePress() && oneMax < 100){
      lcd.clear();
      oneMax++;
      bklTime = millis();
    }
    if(minus.uniquePress() && oneMax > 0){
      lcd.clear();
      oneMax--;
      bklTime = millis();
    }
  }

  if(menuCount == 7){
    //set start time for channel two
    lcd.setCursor(0,0);
    lcd.print("Channel 2 Start");
    lcd.setCursor(0,1);
    printMins(twoStartMins, true);
    if(plus.uniquePress() && twoStartMins < 1440){
      twoStartMins++;
      bklTime = millis();
    }
    if(minus.uniquePress() && twoStartMins > 0){
      twoStartMins--;
      bklTime = millis();
    }
  }

  if(menuCount == 8){
    //set end time for channel two
    lcd.setCursor(0,0);
    lcd.print("Channel 2 End");
    lcd.setCursor(0,1);
    printMins(twoStartMins+twoPhotoPeriod, true);
    if(plus.uniquePress() && twoPhotoPeriod < 1440){
      twoPhotoPeriod++;
      bklTime = millis();
    }
    if(minus.uniquePress() && twoPhotoPeriod > 0){
      twoPhotoPeriod--;
      bklTime = millis();
    }
  }

  if(menuCount == 9){
    //set fade duration for channel two
    lcd.setCursor(0,0);
    lcd.print("Channel 2 Fade");
    lcd.setCursor(0,1);
    printMins(twoFadeDuration, false);
    if(plus.uniquePress() && twoFadeDuration > twoPhotoPeriod/2){
      twoFadeDuration++;
      bklTime = millis();
    }
    if(minus.uniquePress() && twoFadeDuration > 0){
      twoFadeDuration--;
      bklTime = millis();
    }
  }

  if(menuCount == 10){
    //set intensity for channel two
    lcd.setCursor(0,0);
    lcd.print("Channel 2 Max");
    lcd.setCursor(1,1);
    lcd.print(twoMax);
    if(plus.uniquePress() && twoMax < 100){
      lcd.clear();
      twoMax++;
      bklTime = millis();
    }
    if(minus.uniquePress() && twoMax > 0){
      lcd.clear();
      twoMax--;
      bklTime = millis();
    }
  }

  if(menuCount == 11){
    //set start time for channel three
    lcd.setCursor(0,0);
    lcd.print("Channel 3 Start");
    lcd.setCursor(0,1);
    printMins(threeStartMins, true);
    if(plus.uniquePress() && threeStartMins < 1440){
      threeStartMins++;
      bklTime = millis();
    }
    if(minus.uniquePress() && threeStartMins > 0){
      threeStartMins--;
      bklTime = millis();
    }
  }

  if(menuCount == 12){
    //set end time for channel three
    lcd.setCursor(0,0);
    lcd.print("Channel 3 End");
    lcd.setCursor(0,1);
    printMins(threeStartMins+threePhotoPeriod, true);
    if(plus.uniquePress() && threePhotoPeriod < 1440){
      threePhotoPeriod++;
      bklTime = millis();
    }
    if(minus.uniquePress() && threePhotoPeriod > 0){
      threePhotoPeriod--;
      bklTime = millis();
    }
  }

  if(menuCount == 13){
    //set fade duration for channel three
    lcd.setCursor(0,0);
    lcd.print("Channel 3 Fade");
    lcd.setCursor(0,1);
    printMins(threeFadeDuration, false);
    if(plus.uniquePress() && threeFadeDuration > threePhotoPeriod/2){
      threeFadeDuration++;
      bklTime = millis();
    }
    if(minus.uniquePress() && threeFadeDuration > 0){
      threeFadeDuration--;
      bklTime = millis();
    }
  }

  if(menuCount == 14){
    //set intensity for channel three
    lcd.setCursor(0,0);
    lcd.print("Channel 3 Max");
    lcd.setCursor(1,1);
    lcd.print(threeMax);
    if(plus.uniquePress() && threeMax < 100){
      lcd.clear();
      threeMax++;
      bklTime = millis();
    }
    if(minus.uniquePress() && threeMax > 0){
      lcd.clear();
      threeMax--;
      bklTime = millis();
    }
  }

  if(menuCount == 15){
    //set start time for channel four
    lcd.setCursor(0,0);
    lcd.print("Channel 4 Start");
    lcd.setCursor(0,1);
    printMins(fourStartMins, true);
    if(plus.uniquePress() && fourStartMins < 1440){
      fourStartMins++;
      bklTime = millis();
    }
    if(minus.uniquePress() && fourStartMins > 0){
      fourStartMins--;
      bklTime = millis();
    }
  }

  if(menuCount == 16){
    //set end time for channel four
    lcd.setCursor(0,0);
    lcd.print("Channel 4 End");
    lcd.setCursor(0,1);
    printMins(fourStartMins+fourPhotoPeriod, true);
    if(plus.uniquePress() && fourPhotoPeriod < 1440){
      fourPhotoPeriod++;
      bklTime = millis();
    }
    if(minus.uniquePress() && fourPhotoPeriod > 0){
      fourPhotoPeriod--;
      bklTime = millis();
    }
  }

  if(menuCount == 17){
    //set fade duration for channel four
    lcd.setCursor(0,0);
    lcd.print("Channel 4 Fade");
    lcd.setCursor(0,1);
    printMins(fourFadeDuration, false);
    if(plus.uniquePress() && fourFadeDuration > fourPhotoPeriod/2){
      fourFadeDuration++;
      bklTime = millis();
    }
    if(minus.uniquePress() && fourFadeDuration > 0){
      fourFadeDuration--;
      bklTime = millis();
    }
  }

  if(menuCount == 18){
    //set intensity for channel four
    lcd.setCursor(0,0);
    lcd.print("Channel 4 Max");
    lcd.setCursor(1,1);
    lcd.print(fourMax);
    if(plus.uniquePress() && fourMax < 100){
      lcd.clear();
      fourMax++;
      bklTime = millis();
    }
    if(minus.uniquePress() && fourMax > 0){
      lcd.clear();
      fourMax--;
      bklTime = millis();
    }
  }

  if(menuCount == 19){
    //set hours
    lcd.setCursor(0,0);
    lcd.print("Set Time: Hrs");
    lcd.setCursor(0,1);
    printHMS(hour, minute, second);
    if(plus.uniquePress() && hour < 23){
      hour++;
      bklTime = millis();
    }
    if(minus.uniquePress() && hour > 0){
      hour--;
      bklTime = millis();
    }
  setDate(second, minute, hour, dayOfWeek, dayOfMonth, month, year);
  }
  
  if(menuCount == 20){
    //set minutes
    lcd.setCursor(0,0);
    lcd.print("Set Time: Mins");
    lcd.setCursor(0,1);
    printHMS(hour, minute, second);
    if(plus.uniquePress() && minute < 59){
      minute++;
      bklTime = millis();
    }
    if(minus.uniquePress() && minute > 0){
      minute--;
      bklTime = millis();
    }
  setDate(second, minute, hour, dayOfWeek, dayOfMonth, month, year);
  }
}

