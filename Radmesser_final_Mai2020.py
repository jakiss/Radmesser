import RPi.GPIO as GPIO
import time
import os
import serial
import pynmea2
import string
import glob

# Temperatursensor erkennen und ansprechen, ist er nicht da
# -> keine Startroutine
base_dir='/sys/bus/w1/devices/'
device_folder = glob.glob(base_dir + '28*')[0]
print(device_folder)
device_file=device_folder+'/w1_slave'

# Das erste Mal die serielle Schnittstelle abfragen
# Startzeit rund 17 Sekunden laut Datenblatt
serialPort = serial.Serial("/dev/ttyS0", 9600, timeout=2)

# File-Pointer definieren
file=open('testmessung00.txt', 'w')
f=file
j=0
test="messdaten"
# bis eine neue Datei geschrieben werden kann
x=0
while(os.path.exists("{0}{1}.txt".format(test, x))):
    x=x+1
#V oreinstellungen
GPIO.setmode(GPIO.BCM)
GPIO.setwarnings(False)
# Variabeln definieren
PIN_TRIGGER=19
PIN_ECHOVorne=24
PIN_ECHOHinten=23
PIN_RICHTIG=21
PIN_FALSCH=20
PIN_DOWN=6
# PINs korrekt belegen
GPIO.setup(PIN_TRIGGER, GPIO.OUT)
GPIO.setup(PIN_ECHOVorne, GPIO.IN)
GPIO.setup(PIN_ECHOHinten, GPIO.IN)
GPIO.setup(PIN_RICHTIG, GPIO.OUT)
GPIO.setup(PIN_FALSCH, GPIO.OUT)
GPIO.setup(PIN_DOWN, GPIO.IN)
# Zu Beginn die OUTPUTs einstellen
GPIO.output(PIN_FALSCH, GPIO.HIGH)
GPIO.output(PIN_RICHTIG, GPIO.LOW)
GPIO.output(PIN_TRIGGER, GPIO.LOW)
time.sleep(0.5)
begin=time.time()
# Definition des Exit-Falls
def shutdown(channel):
    f.close()
    os.system("sudo shutdown -h now")
# Definition des Exit-Events
GPIO.add_event_detect(PIN_DOWN, GPIO.FALLING,callback=shutdown)
# Unterprogramm: ruft den Temperatursensor auf
def read_temp_raw():
    ft=open(device_file,'r')
    lines=ft.readlines()
    ft.close()
    return lines
# Unterprogramm wandelt Rueckmeldung des Temperatursensors in lesbares Format
def read_temp():
    lines=read_temp_raw()
    while (lines[0].strip()[-3:]!='YES'):
        time.sleep(0.2)
        lines=read_temp_raw()
    equals_pos=lines[1].find('t=')
    if(equals_pos!=-1):
        temp_string=lines[1][equals_pos+2:]
        temp_c=float(temp_string)/1000.0
	# Temperatur wird um den Faktor 1000 zu gross 
	# -> siehe Datenblatt DS18B20
    return temp_c
#Unterprogramm um beide Ultraschallsensoren gleichzeitig verwenden zu konnen
def UP():
    #Trigger-Impuls fur beide Ultraschallsensoren setzen
    GPIO.output(PIN_TRIGGER, GPIO.HIGH)
    time.sleep(0.00001)
    GPIO.output(PIN_TRIGGER, GPIO.LOW)
    #Zeitvariablen definieren
    t_begin=time.time()
    t_start=time.time()
    t_endvorne=t_start
    t_endhinten=t_start
    #Warten bis beide Echo-Pins 1 sind
    while((GPIO.input(PIN_ECHOVorne)==0)|(GPIO.input(PIN_ECHOHinten)==0)):
        t_start=time.time()
        #nach Zeituberschreitung (100ms) Schleife verlassen
        if(t_start-t_begin>0.1):
            break
    #Warten bis beide wieder Rucksignal bekommen haben
    while((GPIO.input(PIN_ECHOVorne)==1)|(GPIO.input(PIN_ECHOHinten)==1)):
        if(GPIO.input(PIN_ECHOVorne)==1):
            t_endvorne=time.time()
        if(GPIO.input(PIN_ECHOHinten)==1):
            t_endhinten=time.time()
    #Zeitdifferenz berechnen
    t_diffvorne=t_endvorne-t_start
    t_diffhinten=t_endhinten-t_start
    #Strecke berechnen mit v=342m/s
    wayvorne=t_diffvorne*17150
    wayhinten=t_diffhinten*17150
    #Allgemeine Zeit berechnen
    t_gesamt=t_start-begin
    #In Datei schreiben
    f.write("%1.3f,"%t_gesamt)
    f.write("%2.1f,"%wayvorne)
    f.write("%2.1f,"%wayhinten)
    f.write("\n")
    #LEDs zur Statusanzeige ansteuern
    if((wayvorne<5)|(wayvorne>2000)|(wayhinten>2000)|(wayhinten<5)):
        GPIO.output(PIN_FALSCH, GPIO.HIGH)
    else:
        GPIO.output(PIN_FALSCH, GPIO.LOW)
    return 0

#Startroutine, Ultraschallsensoren werden auf Funktion getestet
GPIO.output(PIN_FALSCH, GPIO.HIGH)
messwert=0
while((messwert<10)|(messwert>500)):
    GPIO.output(PIN_TRIGGER, GPIO.HIGH)
    time.sleep(0.00001)
    GPIO.output(PIN_TRIGGER, GPIO.LOW)
    t_startup=time.time()
    t_endup=t_startup
    while(GPIO.input(PIN_ECHOVorne)==0):
        t_startup=time.time()
    while(GPIO.input(PIN_ECHOVorne)==1):
        t_endup=time.time()
    t_diffup=t_endup-t_startup
    messwert=t_diffup*17150
messwert=0
while((messwert<10)|(messwert>500)):
    GPIO.output(PIN_TRIGGER, GPIO.HIGH)
    time.sleep(0.00001)
    GPIO.output(PIN_TRIGGER, GPIO.LOW)
    t_startup=time.time()
    t_endup=t_startup
    while(GPIO.input(PIN_ECHOHinten)==0):
        t_startup=time.time()
    while(GPIO.input(PIN_ECHOHinten)==1):
        t_endup=time.time()
    t_diffup=t_endup-t_startup
    messwert=t_diffup*17150
#Test der Ultraschallsensoren erfolgreich abgeschlossen
GPIO.output(PIN_FALSCH, GPIO.LOW)
#Das GPS-Modul wird im Folgenden hoch gefahren
z=0
while(z<30):
    serialPort = serial.Serial("/dev/ttyS0", 9600, timeout=2)
    GPIO.output(PIN_RICHTIG, GPIO.HIGH)
    GPIO.output(PIN_FALSCH, GPIO.HIGH)
    time.sleep(0.5)
    GPIO.output(PIN_RICHTIG, GPIO.LOW)
    GPIO.output(PIN_FALSCH, GPIO.LOW)
    time.sleep(0.5)
    z=z+1
GPIO.output(PIN_RICHTIG, GPIO.HIGH)
GPIO.output(PIN_FALSCH, GPIO.LOW)
#an dieser Stelle ist noch ein Test des GPS-Moduls sinnvoll
while True:
    messzahl=0#Zahler fur Messungen
    file=open("{0}{1}.txt".format(test, x), 'w')
    # Datei mit entsprechender Nummer offnen
    f=file
    # verkuerzter Filepointer
    temp_c=read_temp()
    # Temperaturabfrage und in Datei schreiben
    f.write("Temperatur,")
    f.write("%f"%temp_c)
    f.write("\n")
    while(messzahl<5000):
    # 5000Messungen in einer Datei
        if((messzahl%100)==0):
	# alle 100 Messwerte wird GPS-Position hinzugefugt, ca. alle 2,5 Sekunden
            serialPort = serial.Serial("/dev/ttyS0", 9600, timeout=2)
	    # neue GPS-Position abfragen
            str =serialPort.readline()
	    # Ubermitteltes Protokoll lesen
            f.write(str.decode())
	    # in Datei schreiben, encode -> Schnittstelle liefert Bytes 
        UP()#Messung durchfuhren
        messzahl=messzahl+1#Zahler fur Messungen hochzahlen
    x=x+1#Zahler fur nachste Datei
    f.close()#alte Datei schliessen
    if(x>25000):
    #wenn mehr als 25000 Dateien erstellt wurden gibt es einen Alarm
        GPIO.output(PIN_RICHTIG, GPIO.LOW)
        GPIO.output(PIN_FALSCH, GPIO.HIGH)
    else:
        GPIO.output(PIN_RICHTIG, GPIO.HIGH)