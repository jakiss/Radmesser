module main;

import std.stdio;
import std.typecons;
import std.csv;
import std.file;
import std.array;
import std.string;
import std.conv;
import std.algorithm.searching;
import std.math;

const float amind=60; //mindest Abstand, muss bei einem Fahrrad circa 60cm sein (Lenker und Aussenspiegel), kleinerer Abstand bedeutet einen Unfall
const float amax=1400; //14m sind die maximale Distanz, welche durch die Ultraschallsensoren gemessen werden koennen. Typische Maximalwerte liegen jedoch bei circa 12m

const float amaxuber=400;
const float lower=0.95;
const float higher=1.05;
const int empfindlichkeit=15;
const int empfindlichkeitstart=1;
const float mindnouber=400;//Abstand, der mindestens gegeben sein muss, bevor ein Ueberholvorgang stattfinden kann
const float strasse =200.0;//Strassenbreite
int drivenumber;

int globalcount=0;

/*
struct fuer die gemessenen Daten, diese sind als messdatenX.txt vorhanden, dabei ergibt sich folgender Aufbau:

Zeit seit Systemstart in Sekunden, Distanz vorderer Ultraschallsensor in cm, Distanz hinterer Ultraschallsensor in cm
Zeit seit Systemstart in Sekunden, Distanz vorderer Ultraschallsensor in cm, Distanz hinterer Ultraschallsensor in cm
.
.
.
GPRMC (Vgl. GPRMC-GPS-Format)


Die Daten werden in dem struct gesammelt
*/
struct measuredata{
    int number;
    float time;//Zeit seit Systemstart in Sekunden
    float vorne;// Distanz vorderer Ultraschallsensor in cm
    float hinten;//Distanz hinterer Ultraschallsensor in cm
    float utctime;//UTC-Time, Zeitangabe, fuer welche Sommer und Winterzeit, sowie die Breitenverschiebung beruecksichtigt werden muss
    float north;//noerdlicher/suedlicher Breitengrad
    float east;//oestlicher/westlicher Laengengrad
    float date;//Datum
    float speed;//Geschwindigkeit Fahrradfahrer laut GPS-Modul
    float orientation=-1.0; //Fahrtrichtung bezogen auf den Nordpol
    float temp=17.0;
    //folgende Variabeln werden nur benoetigt, wenn ein Ueberholvorgang vorliegt
    float overtaking;//Ueberholabstand, es muss die Distanz zwischen Fahrrad und KFZ abgezogen werden
    float speedKFZ;//Geschwindigkeit des KFZ, muss noch implementiert und getestet werden
    float lenghtKFZ;//Laenge des KFZ, muss noch implementiert und getestet werden
};

/*
Bei den Geodaten handelt es sich um die jeweiligen GPS-Koordinaten, ohne Abstandswerte
Es werden hier nur die GPS-Koordinaten aufgefuehrt, bei measuredata werden alle Messwerte der Ultraschallsensoren gelistet mit allen GPS-Informationen
Die Ultraschallsensoren messen rund 100 Mal haeufiger als das GPS-Modul
*/
struct geodata{//Variablen-Namen Vgl. measuredata
    float utctime;
    float north;
    float east;
};

/*
Alle Daten zu einer Fahrt
Hierbei wird eine neue Fahrt angelegt, wenn die zwischen zwei GPS-Uhrzeit-Angaben ein zeitlicher Unterschied von 2 Minuten liegt
*/
struct fahrt{
    measuredata[] inputdata; //(Vgl. oben) alle Messwerte
    geodata[] geodaten; //(Vgl. oben) alle GPS-Koordinaten
    float gesamtstrecke; //Strecke, welche bei einer Fahrt zurueckgelegt wurde
    measuredata[] overtaking;//nur bei erkannten Ueberholvorgaengen
};

fahrt current_drive; //aktuelle Fahrt (Vgl. struct fahrt)

fahrt[] entiredata; //alle Daten werden in einem gesammelten Array zusammengetragen (mehrere Fahrten)


float coordinateconvert(string eingang){
    /*
    Unterprogramm zur Umwandlung der Koordinaten
    Im GPRMC-Format liegen diese in folgendem Format vor: Grad Minuten, Dezimalminuten (fuer Stuttgart: 4840.88970 und 00859.86078)
    Die Koordinaten sollen aber als Grad und Dezimalgrade vorliegen (Alle gaenigen Systeme arbeiten mit Dezimalgraden)
    Uergabewert ist ein string, die Laenge- bzw. Breitenangabe im Rohformat, wie sie eingelesen wird
    Rueckgabewert ist ein Float, die Laenge- bzw. Breitenkoordinate im Dezimalgrad-Format
    */
    float startvalue=to!double(eingang);// aus einer Datei wird ein String gelesen, dieser muss konvertiert werden, cast ist nicht moeglich bei dieser Konvertierung
    int intvalue=to!int(startvalue/100);//Die Gradangabe wird extrahiert, bei Integer werden bei Divisionen alle Nachkommastellen entfernt
    float floatvalue=startvalue-intvalue*100;//Die Gradangabe wird von dem Gesamtwert abgezogen, es bleiben nur noch die Minuten uebrig
    float returnvalue=intvalue+floatvalue/60;//Die Dezimalgradangabe setzt sich aus dem Gradwert und den Minuten/60 zusammen
    return returnvalue;
}

void readcsv(string filename){//CSV-Datei einlesen
    /*
    Es werden die Daten mit den Messwerten der Kesselbox eingelesen
    */
    File file=File(filename, "r"); //Dateiname kommt aus Hauptprogramm
    //Die folgenden Variablen dienen dazu die GPS-Daten den einzelnen Messwerten zuzuordnen
    float utctime; //UTC-Zeit (Grennwich-Time)
    float north; //noerdlicher Breitengrad
    float east; //Laengengrad
    float date; //Datum
    float speed; //Geschwindigkeit
    float orientation=-1.0; //Fahrtrichtung bezogen auf den Nordpol
    float temp=17.0;
    float oldutctime; //letzte Uhrzeitangabe, dient dazu den zeitlichen Abstand zwischen der alten und neuen Messung zu ermitteln
    float olddate; //letzte Datumsangabe, dient dazu zu ermitteln, ob die Fahrt innerhalb eines Tages stattfand, bzw um zwei Fahrten zu unterscheiden

    while(!file.eof()){ //Es wird immer bis zum Dateiende gelesen
        globalcount++; //Zahler fur alle Zeilen

        string line=file.readln();//Einzelne Zeile Einlesen als String
        if(canFind(line,"Temperatur")){//Temperaturangabe ist durch Temperatur gekennzeichnet
            auto split1=line.split(",");//Es darf nur die Zahl als Temperatur verwendet werden - bisher noch nicht funktionsfaehig
            temp=to!double(split1[1]);
        }else if(count(line,",")>2){ //Die letzte Zeile jeder Datei ist leer, deshalb nur die vollen Zeilen verwenden
            auto split1=line.split(",");//Da es sich um eine CSV-Datei handelt Spalten an Kommata auftrennen, die Zeilen sind durch Kommata getrennt
            if(split1[0]=="GPS" || canFind(line, "N") || canFind(line, "*") || canFind(line, "E") || canFind(line, "V") || canFind(line,"F") || canFind(line,"C") || canFind(line,"B") || canFind(line, "GPRMC")){//Zeile wird als GPS-Inhalt erkannt und gesondert behandelt
                //Zeile mit GPS-Daten enthaelt den String GPRMC
                if(canFind(line,"GPRMC")==1){
                    auto splitgps=line.split(",");//GPS-Daten sind durch Kommata getrennt
                    if(splitgps[2]=="A"){//A impliziert, dass GPS-Daten gueltig sind
                        oldutctime=utctime;//utctime enhaelt bisher noch die Zeitangabe des vorherigen GPRMC-Datensatzes, dies ist nun die neue alte Zeitangabe
                        olddate=date;//Vgl oldutctime
                        utctime=to!double(splitgps[1]);//Eingelesen wird ein String, dieser wird in eine Zahl gewandelt
                        if(splitgps[4]=="N"){// noerdlich des Aequators
                            north=coordinateconvert(splitgps[3]);// Koordinaten werden konvertiert
                        }
                        if(splitgps[4]=="S"){// suedlich des Aequators
                            north=-1*coordinateconvert(splitgps[3]);//Koordinaten werden konvertiert
                        }
                        if(splitgps[6]=="E"){//oestlich des Nullmeridians
                            east=coordinateconvert(splitgps[5]);//Koordinaten werden konvertiert
                        }
                        if(splitgps[6]=="W"){//westlich des Nullmeridians
                            east=-1*coordinateconvert(splitgps[5]);//Koordinaten werden konvertiert
                        }
                        float speedk=to!double(splitgps[7]);//Gewschwindigkeit muss in Zahl umgesetzt werden
                        speed=speedk/0.53996;//Knoten werden in kmh umgesetzt
                        date=to!double(splitgps[9]);//Datum wird in Zahl gewandelt
                        if(splitgps[8]!=""){//Bei Stillstand kann keine Bewegungsrichtung angegeben werden
                            orientation=to!double(splitgps[8]);//Bewegungsrichtung wird in eine Zahl gewandelt
                        }
                        else{
                            orientation=-1.0;//Ist keine Bewegungsrichtung gegeben wird diese -1, eindeutig, dass es sich dann um ein ungueltiges Datum handelt
                        }

                    }
                    if(/*olddate!=date||*/utctime-oldutctime<0||utctime-oldutctime>100){//Bei einem zeitlichen Unterschied von ueber 1:50 Minuten wird eine neue Fahrt angefangen, ist die neue Zeit kleiner als die alte, hat diese am vorherigen Tag stattgefunden
                        current_drive=automatisch_erkennen(current_drive);//Es werden die Ueberholvorgange aus den Messwerten ermittelt (UP siehe unten)
                        entiredata~=current_drive;//Die erkannten Ueberholvorgaenge werden zu den gesamten Daten dazugelegt
                        destroy(current_drive);//Die bisherigen Daten werden wieder geloescht - nur die Ueberholovrgaenge werden behalten
                    }
                    geodata newgeodata;//Handelt es sic h immer noch um die gleiche Fahrt, werden die Geodaten gesondert abgespeichert
                    newgeodata.utctime=utctime;
                    newgeodata.north=north;
                    newgeodata.east=east;
                    current_drive.geodaten~=newgeodata;//Die Geodaten werden der aktuellen Fahrt zugeordnet
                }
            }else{//Zeile enthalt normale Messwerte, nicht GPS oder anderes
                auto splittime1=(split1[0]).split(" ");//String wird an den Leerezichen aufgetrennt
                double time=0;
                int leerzeichenout;//Gesamtzahl der Leerzeichen am Anfang der Zeile
                for(int leerzeichen; (splittime1[leerzeichen])=="";leerzeichen++){//Es wird die Zahl der zu Beginn stehenden Leerzeichen ermittelt
                    leerzeichenout=leerzeichen+1;
                }
                if(canFind(splittime1, "\n")){}
                else{
                    time=to!double(splittime1[leerzeichenout]);//Die Zeit steht hinter den fuehrenden Leerzeichen
                    auto split2=(split1[1]).split(" ");//Bei den Messwerten wird geprueft, ob Leerzeichen vorhanden sind
                    auto split3=(split1[2]).split(" ");//Bei den Messwerten wird geprueft, ob Leerzeichen vorhanden sind
                    if(split2[0]!=""&&split3[0]!=""){//Daten werden nur dann verwendet, wenn keine Leerzeichen enthalten sind
                        double f1=to!double(split2[0]); //vorderer Messwert
                        double f2=to!double(split3[0]); //hinterer Messwert
                        if(f1>amind&&f2>amind&&f1<amax&&f2<amax){//Distanz kleiner mindestanforderung, also auserhalb Fahrradlenker oder groesser wie maximalmoeglich, technische Grenze HC-SR04 oder Begrenzgung der Testumgebung: delete
                            measuredata input;//Neue Messwert-struct wird erstellt
                            //Messwert-struct wird mit den GPS-Daten und den Abstandswerten befuellt
                            input.time=time;
                            input.vorne=f1;
                            input.hinten=f2;
                            input.utctime=utctime;
                            input.north=north;
                            input.east=east;
                            input.date=date;
                            input.temp=temp;
                            input.speed=speed;
                            input.orientation=orientation;
                            current_drive.inputdata~=input;
                        }
                    }
                }
            }
        }

    }
    file.close();//Datei wird nach vollstaendigem Lesen geschlossen
}

fahrt automatisch_erkennen(fahrt aktuelle_fahrt){
    /*
    UP uebernimmt alle Schritte, um erfolgreich die Ueberholvorgaenge aus den Messdaten zu ermitteln
    Es werden Messdaten eingegeben und diese dann in Ueberholdaten gewandelt. Das Datenformat aendert sich dabei nicht
    */
    aktuelle_fahrt.inputdata=glattung(aktuelle_fahrt.inputdata);//Messwerte werden in einem UP gegleattet
    aktuelle_fahrt.overtaking=erkennen2(aktuelle_fahrt.inputdata);//Ueberholvorgaenge werden mit dem UP erkannt
    aktuelle_fahrt.gesamtstrecke=calcualtedistance(aktuelle_fahrt.geodaten);//Es wird die zurueckgelegte Distanz ermittelt
    aktuelle_fahrt.inputdata=null;//Die Daten werden vernichtet, um wieder Arbeitsspeicher freizugeben
    aktuelle_fahrt.geodaten=null;//Die Daten werden vernichtet, um wieder Arbeitsspeicher freizugeben
    drivenumber++;//Zahl der Fahrten wird um eines hoch gesetzt
    return aktuelle_fahrt;
}

measuredata[]glattung(measuredata[] ret){
    /*
    Die Ultraschallsensorenfuehren teilweise fehlerhafte Messungen durch
    Messfehler koennen daran erkannt werden, dass diese zu stark von ihren Vor- und Nachfolgern (benachbarte Messwerte) abweichen
    */
    int zeilen=count(ret);//Wird benoetigt, da mit einer for-Schleife gearbietet wird - Foreach ist nicht moeglich, da Startwert ungleich null ist
    float faktor=0.9;//maximaler Abweichungsfaktor nach unten
    float faktor2=1.1;//maximaler Abweichungsfaktor nach oben
    for(int i=1; i<(zeilen-1);i++){//Die For-Schleife beginnt nicht bei nullten Element, sondern beim ersten, da von jedem Element das vorherige und das darauffolgende benoetigt werden
        if((ret[i-1].vorne*faktor)>ret[i].vorne && (faktor*ret[i+1].vorne)>ret[i].vorne){//bei den vorderen Sensor sind die benachbarten Messwerte um 10% groesser
            ret[i].vorne=(ret[i-1].vorne+ret[i+1].vorne)/2;//Der Messwert wird durch den Durchschnitt der benachbarten Messwerte ersetzt
        }
        if((ret[i-1].hinten*faktor)>ret[i].hinten && (faktor*ret[i+1].hinten)>ret[i].hinten){//bei den hinteren Sensor sind die benachbarten Messwerte um 10% groesser
            ret[i].hinten=(ret[i-1].hinten+ret[i+1].hinten)/2;//Der Messwert wird durch den Durchschnitt der benachbarten Messwerte ersetzt
        }
        if((ret[i-1].vorne*faktor2)<ret[i].vorne && (faktor2*ret[i+1].vorne)<ret[i].vorne){//bei den vorderen Sensor sind die benachbarten Messwerte um 10% kleiner
            ret[i].vorne=(ret[i-1].vorne+ret[i+1].vorne)/2;//Der Messwert wird durch den Durchschnitt der benachbarten Messwerte ersetzt
        }
        if((ret[i-1].hinten*faktor2)<ret[i].hinten && (faktor2*ret[i+1].hinten)<ret[i].hinten){//bei den hinteren Sensor sind die benachbarten Messwerte um 10% kleiner
            ret[i].hinten=(ret[i-1].hinten+ret[i+1].hinten)/2;//Der Messwert wird durch den Durchschnitt der benachbarten Messwerte ersetzt
        }
    }
    return ret;
}

int writecsvfromstruct(string filename,measuredata[] inputdata, bool inorub){
    //Alle Ueberholvorgaenge in eine Tabelle schreiben, als Spaltentrenner dienen Kommata
    File f=File(filename,"w");//Datei im Schreibmodus oeffnen
    if(inorub){
            //Option wird aktuell nicht genutzt
        f.writeln("Zeitstempel,vorne,hinten,temp,Zeit,Datum,Lange,Breite,Geschw,Orientierung");
        foreach(measuredata input; inputdata){
            f.write(input.time,",");
            f.write(input.vorne,",");
            f.write(input.hinten,",");
            f.write(input.temp,",");
            f.write(input.utctime,",");
            f.write(input.date,",");
            f.write(input.north,",");
            f.write(input.east,",");
            f.write(input.speed,",");
            f.write(input.orientation,",");
            f.write("\n");
        }
    }else {
        f.writeln("Abstand,Zeit,Datum,Lange,Breite,Geschwindigkeit Fahrrad, Geschwindigkeit KFZ, Lange KFZ,");
        foreach(measuredata input; inputdata){
            if(input.overtaking>0&&(input.north>0||input.north<0)&&(input.east<0||input.east>0)){
                f.write(input.overtaking,",");
                f.write(input.utctime,",");
                f.write(input.date,",");
                f.write(input.north,",");
                f.write(input.east,",");
                f.write(input.speed,",");
                f.write(input.speedKFZ,",");
                f.write(input.lenghtKFZ,",");
                f.write("\n");
            }
        }
    }
    f.close();
    return 100;
}

measuredata[] erkennen(measuredata[]inputdata){
    /*
    vorherige Version zur Erkennung der Ueberholabstaende
    Aufgrund mehrerer Tests wurde entdeckt, dass dieser Algorithmus zu viele Ueberholvorgaenge erkennt
    Der neue Algorithums ist im UP erkennen2 zu finden
    */
    measuredata[] erkannt;
    float[] uberhol;
    float amindest=strasse+amind;
    int flaguber;
    int flaguber2;
    int flagunter;
    float lastuberholtime=0;
    float begin1;
    float end1;
    foreach(measuredata input; inputdata){
        float vorne=input.vorne;
        float hinten=input.hinten;

        if((input.time)>20.0){//alles innerhalb der ersten 20 Sekunden wird nicht berucksichtigt
            if( (vorne*higher<hinten) && vorne<amindest ){ //vorderer Wert ist um uber 40 Prozent kleiner als hinterer, uberholvorgang erst ab 2,5m erkennen
                if(flaguber==0){
                    begin1=input.time;
                }
                flaguber++; //Marker setzen
                flagunter=0;
            }else if( (hinten<amindest) && (vorne<amindest) && (flaguber>empfindlichkeitstart) && (hinten*lower)<vorne && (hinten*higher)>vorne ){
                if(flaguber2==0){
                    end1=input.time;
                }
                uberhol~=(vorne+hinten)/2;
                flaguber2++;
                flagunter=0;
            }else if( (vorne*lower)>hinten && (vorne>amindest) && (flaguber2>empfindlichkeit) ){
                int numberarr=uberhol.count();
                float gesamtuberhol=0;
                for(int zeilencount; zeilencount<numberarr; zeilencount++){
                    gesamtuberhol=gesamtuberhol+uberhol[zeilencount];
                }
                float timeforspeed=end1-begin1;
                float timeforlength=input.time-end1;
                float overtaking=gesamtuberhol/numberarr;
                float distanceforspeed=overtaking/20;
                float speed=(distanceforspeed)/timeforspeed;
                float length=(speed*timeforlength)/25;

                measuredata erkannt1;
                erkannt1=input;
                erkannt1.speedKFZ=input.speed+speed;
                erkannt1.lenghtKFZ=length;
                erkannt1.overtaking=overtaking;
                //erkannt1.speedKFZ=flaguber;
                //erkannt1.lenghtKFZ=bearbeitet[i][3];
                float timediff=input.time-lastuberholtime;
                if(numberarr>3 && input.time-lastuberholtime>1){
                    erkannt~=erkannt1;
                }
                uberhol.destroy();
                lastuberholtime=input.time;
                //erkannt~=bearbeitet[i-flaguber2/2];
                flaguber=0;
                flaguber2=0;
            }else{
                flagunter++;
            }
            if(flagunter>50){
                flaguber=0;
                flaguber2=0;
                flagunter=0;
            }
        }

    }
    return erkannt;
}

measuredata[] erkennen2(measuredata[]inputdata){
    /*
    Verbesserter Algorithmus zur Erkennung der Ueberholvorgaenge
    State-Machine, mit den Zustaenden s1 bis s6
    Es ist immer genau ein Zustand wahr
    Es werden die Messdaten uebergeben und die erkannten Ueberholvorgaenge zurueckgeliefert
    */
    measuredata[] erkannt;//Alle Erkannten Ueberholvorgaenge, welche nacher an das Hauptprogramm zurueckgeliefert werden
    float[] uberhol;//Um eine moeglichst genaue Distanz zwischen KFZ und Auto zu ermitteln, wird ein Durchschnittswert der verschieden Messwerte ermittelt
    float amindest=strasse+amind;
    bool s1, s2, s3, s31, s32, s4, s41, s42, s5, s51, s52, s6;//verschiedene Zustaende fuer die State-Maschine
    s1=true;//Der erste Zustand wird auf wahr gesetzt
    float t0, t1, t2, t3, t4;//Zeiten zur Bestimmung der Ueberholvorgaenge
    foreach(measuredata input; inputdata){//es werden alle Messwerte durchgearbeitet
        float vorne=input.vorne;//der aktuelle Messwert wird in eine Variable geschrieben
        float hinten=input.hinten;

        if((input.time)>20.0){//Die allerersten Messwerte werden nicht innerhalb der ersten 20 Sekunden verwendet
            if(s1&&vorne>mindnouber&&hinten>mindnouber){//mindester seitlicher Abstand, sonst kein Uberholen moglich, es muss ausreichend Platz links des Fahrradfahrers sein
                s2=true;//wenn ausreichend Platz ist, dann wird der naechste Zustand erreicht
                s1=false;//aktueller Zustand wird verlassen
                uberhol.destroy();//Die bisherigen Messwerte zur Ermittlung des Ueberholvorgangs werden geloescht
            }else if(s2){//darf beliebig lange in dem zustand verbleiben, muss immer noch genug Platz sein
                if(vorne>mindnouber&&hinten>mindnouber){//beide Messwerte groesser als der Maximalabstand
                    s2=true;
                }
                if(vorne>mindnouber&&hinten<amindest){//Der hintere Messwert muss kleiner sein als der maximal moegliche Abstand, ansonst kann es kein Ueberholvorgang sein
                    s3=true;
                    s2=false;
                    t0=input.time;
                }
            }else if(s3){//KFZ wird vom hinteren Sensor erfasst, kommt von s2
                if(input.time-t0>3){//off-timer, der Zustand darf nur 3 Sekunden vorhanden sein, danach muss das KFZ von beiden Ultraschallsensoren erfasst werden, danach geht es zurueck in den ersten Zustand
                    s3=false;
                    s1=true;
                }else if(vorne>mindnouber&&hinten<amindest){//immer noch nur vom hinteren Ultraschallsensor erfasst
                    s3=true;
                }else if(vorne<amindest&&hinten<amindest){// das KFZ wird von beiden Ultraschallsensoren erasst, danach geht es ueber in den naechsten Zustand (s4)
                    s4=true;
                    s3=false;
                    t1=input.time;//Die neue Startzeit fuer den Zustand, wenn das KFZ direkt neben dem Fahrrad faehrt
                }else{//bei anderen Messergebnissen faellt es auf einen Wartezustand zurueck
                    s31=true;
                    s3=false;
                }
            }else if(s31){//ein falscher Messwert wurde im Zustand s3 ermittelt - der Zustand s31 erfuellt die gleichen Bedinugungen wie s3
                if(hinten<amindest&&vorne>mindnouber){
                    s3=true;
                    s31=false;
                }else if(hinten<amindest&&vorne<amindest){
                    s31=false;
                    s4=true;
                    t1=input.time;
                }else{
                    s31=false;
                    s32=true;
                }
            }else if(s32){//ein falscher Messwert wurde im Zustand s31 ermittelt - der Zustand s32 erfuellt die gleichen Bedinugungen wie s3 und s31
                if(hinten<amindest&&vorne>mindnouber){
                    s3=true;
                    s32=false;
                }else if(hinten<amindest&&vorne<amindest){
                    s32=false;
                    s4=true;
                    t1=input.time;
                }else{
                    s32=false;
                    s1=true;
                }
            }else if(s4){//Zustand, wenn KFZ direkt neben Fahrrad ist
                if(input.time-t1>25){//off timer, wenn KFZ neben Fahrrad ist, maximal 25 Sekunden, wurde anhand von maximaler KFZ Laenge und minimaler Ueberholgeschwindigkeit ermittelt
                    s4=false;
                    s1=true;
                }else if(hinten<amindest&&vorne<amindest){//wenn beide Messwerte kleiner sind als der entsprechende Abstand, wird der Mittelwert aus den Messwerten der Ultraschallsensoren verwendet, mit diesem wird nachher der Gesamtdurchschnitt bestimmt
                    s4=true;
                    uberhol~=(vorne+hinten)/2;
                }else if(hinten>mindnouber&&vorne<amindest&&input.time-t1>0.1){//Zeit die das KFZ midndestens neben dem Fahrrad verbringen muss
                    s4=false;
                    s5=true;//naechster Zustand, wenn das KFZ aus dem Messbereich der Ultraschallsensoren herausfaehrt
                    t2=input.time;
                }else{//Bei einem Messfehler geht es ueber in die Toleranzfhelerbehandlung
                    s41=true;
                    s4=false;
                }
            }else if(s41){//ein erster Messfehler ist erlaubt, die Bedingungen sind die gleichen, wie bei s4
                if(vorne<amindest&&hinten<amindest){//war es nur ein einmaliger Messfehler, geht es zurueck in den s4-Normalen Zustand
                    s41=false;
                    s4=true;
                }else if(vorne<amindest&&hinten>mindnouber){
                    s41=false;
                    s5=true;
                    t2=input.time;
                }else if(hinten<amindest&&vorne>mindnouber){
                    s41=false;
                    s3=true;
                }else{//zweiter falscher Messwert in Folge
                    s41=false;
                    s42=true;
                }
            }else if(s42){//ein zweiter Messfehler ist erlaubt, die Bedingungen sind die gleichen, wie bei s4 und s41
                if(vorne<amindest&&hinten<amindest){
                    s42=false;
                    s4=true;
                }else if(vorne<amindest&&hinten>mindnouber){
                    s42=false;
                    s5=true;
                    t2=input.time;
                }else if(hinten<amindest&&vorne>mindnouber){
                    s42=false;
                    s3=true;
                }else{//dritter falscher Messwert, dann geht es zurueck in den Anfangszustand
                    s42=false;
                    s1=true;
                }
            }else if(s5){//Herausfahren aus Messbereich, nur noch der vordere Sensor darf das KFZ erfassen
                if(input.time-t2>3){//KFZ darf nicht laenger als 3 Sekunden zum Verlassen des Messbereichs benoetigenm, sonst zurueck in Anfangszustand
                    s5=false;
                    s1=true;
                }else if(hinten>mindnouber&&vorne<amindest){ // Zustand bleibt bestehen
                    s5=true;
                }else if(hinten>mindnouber&&vorne>mindnouber){//KFZ hat Messbereich vollstaendig verlassen
                    s6=true;
                    s5=false;
                    t3=input.time;
                }else{
                    s51=true;
                    s5=false;
                }
            }else if(s51){//erster Messfehler beim Herausfahren aus dem Messbereich
                if(hinten>mindnouber&&vorne<amindest){//kein Messfehler mehr
                    s51=false;
                    s5=true;
                }else if(hinten>mindnouber&&vorne>mindnouber){//KFZ hat Messbereich vollstaendig verlassen
                    s51=false;
                    s6=true;
                    t3=input.time;
                }else{
                    s51=false;
                    s52=true;
                }
            }else if(s52){//zweiter Messfehler beim Herausfahren aus dem Messbereich
                if(hinten>mindnouber&&vorne<amindest){//kein Messfehler mehr
                    s52=false;
                    s5=true;
                }else if(hinten>mindnouber&&vorne>mindnouber){//KFZ hat Messbereich vollstaendig verlassen
                    s52=false;
                    s6=true;
                    t3=input.time;
                }else{//beim zweiten Messfehler faellt das System zurueck in den Anfangszustand
                    s52=false;
                    s1=true;
                }
            }
            if(s6){//KFZ hat Ueberholvorgang abgeschlossen
                measuredata erkannt1;//neuer Ueberholvorgang wird angelegt
                erkannt1=input;//Der Ueberholvorgang wird mit den aktuellen Daten des Messwertes geladen
                int numberarr=uberhol.count();//Die Anzahl der Messwerte, welche als Ueberholvorgaenge ermittelt wurden
                float gesamtuberhol=0;
                //Durchschnitt, welcher als Ueberholabstand gilt
                for(int zeilencount; zeilencount<numberarr; zeilencount++){
                    gesamtuberhol=gesamtuberhol+uberhol[zeilencount];
                }
                float overtaking=gesamtuberhol/numberarr;
                erkannt1.overtaking=overtaking;//Ueberholabstand wird festgesetzt
                float timeforspeed=t1-t0;
                float einfahrzeit=t1-t0;//Zeit, welche das KFZ beim hinteren Ultraschallsensor verbringt
                float timeforlength=t2-t1;
                float ueberholzeit=t2-t1;//Zeit, welche das KFZ neben dem Fahrrad (beide Ultraschallsensoren) verbringt
                float ausfahrzeit=t3-t2;//Zeit, welche das KFZ beim vorderen Ultraschallsensoren verbringt
                //writeln(timeforspeed,"    ",timeforlength,"    ",t3-t2);
                float distanceforspeed=overtaking*0.3;//zu verbessern
                float speed=(distanceforspeed)/timeforspeed;//zu verbessern
                float length=(speed*timeforlength)/25;//zu verbessern
                erkannt1.speedKFZ=input.speed+speed;//zu verbessern
                erkannt1.lenghtKFZ=length;//zu verbessern
                s6=false;//Zustand verlassen
                s1=true;
                if(einfahrzeit<ueberholzeit&&ueberholzeit>ausfahrzeit){//nur wenn das KFZ laenger von beiden Ultraschallsensoren erfasst wird, als nur von den einzelnen Sensoren, ist es ein Ueberholvorgang
                    //Der Ueberholvorgang wird angehaengt
                    erkannt~=erkannt1;
                }
            }
        }

    }
    return erkannt;
}

float calcualtedistance(geodata[] geodatafordistance){
    /*
    Die Distanz wird aus den geographischen Daten errechnet
    */
    float drivendistance=0;
    int numberofdata=count(geodatafordistance);
    //writeln(numberofdata);
    for(int i=0; i<numberofdata-1;i++){//bis auf das letzte Element werden alle Elemente
        float timedif=geodatafordistance[i+1].utctime-geodatafordistance[i].utctime;
        if(timedif>0&&timedif<50){//Zeitdifferenz muss kleiner als 50 Sekunden sein, ansonsten sind die Abstaende zu gross zwischen den
            float eastdif=geodatafordistance[i+1].east-geodatafordistance[i].east;//Die Differenz zwischen den Laengengraden
            float northdif=geodatafordistance[i+1].north-geodatafordistance[i].north;//Die Differenz zwischen den Breitengraden
            float eastdifcos=eastdif*cos(geodatafordistance[i].north);//Die Laengengrade sind unterschiedlich weit entfernt, je nach dem entsprechenden Breitengrad
            float dist=111.3*sqrt(northdif*northdif+eastdifcos*eastdifcos);//Satz des Pythagoras, mit 111,3km multiplizieren, Abstand zwischen zwei Breitengraden, die Laengengrade wurden mit dem Cosinus bearbeitet
            //writeln(dist);
            drivendistance=drivendistance+dist;//Distanz zwischen zwei Koordinatenangaben  wird zur Gesamtdistanz aufaddiert
        }
    }
    return drivendistance;
}

int writegeojson(string filename, measuredata[] writedata){
    /*
    Unterprogramm um eine Geojson-Datei zu erstellen
    Anhand der Ueberholabstaende werden die Punkte eingefaerbt
    Ab 1,5m sind Ueberholvorgaenge gruen, da dies innerhalb von Ortschaften in Ordnung ist
    Unter 1,5m sind die Ueberholvorgaenge gelb, da es sich um eine Unterschreitung des Mindestabstandes handelt
    Unter 1m sind die Ueberholvorgaenge rot, deutliche Unterschreitung des Mindestabstandes
    Unter 0,5m sind die Ueberholvorgaenge dunkelrot, sehr gefaehrlich

    Hierbei wird noch die Lenkerbreite und die Breite des Aussenspiegels des KFZ beruecksichtigt (amind)

    Geojson-Format (Vgl. geojson.io)
    */
    int zeilencount;
    File file=File(filename,"w");//Pointer auf die Datei und Datei im Schreibmodus oeffnen
    file.writeln("{");
    file.writeln("\"type\": \"FeatureCollection\",");
    file.writeln("\"features\": [");
    foreach(measuredata writedat; writedata){//Jeder Datensatz wird als Punkt dargestellt
        float north=writedat.north;
        float east=writedat.east;
        float abstand=writedat.overtaking;
        if(north<90.0 && east<180.0 && abstand<amaxuber && abstand>amind){//Derzeit wird nur kontrolliert, ob es sich bei Nord und Ostkoordinate um eingehaltene Werte handelt. Kontrolle in Sued und West ebenfalls sinnvoll
            /*
            Jeder Ueberholvorgang wird als eigenes Feature angelegt
            Darstellungsfarbe wird wie oben beschrieben dargestellt
            Zusaetzlich werden weitere Informationen zum entsprechenden Ueberholvorgang gegeben
            Weitere Informationen koennen in zusaetzliche Zeilen geschrieben werden
            Ggf. kann ein kontinuierlicher Farbverlauf eingearbeitet werden
            */
            file.writeln("{");
            file.writeln("\"type\": \"Feature\",");
            file.writeln("\"properties\": {");
            file.writeln("\"time\":",writedat.utctime,",");
            file.writeln("\"date\":",writedat.date,",");
            //writeln(abstand);
            if(abstand<(amind+50)){
                file.writeln("\"marker-color\": \"#930000\"");//dunkelrot
            }
            if( abstand<(amind+100) && abstand>(amind+50)){
                file.writeln("\"marker-color\": \"#e2001a\"");//rot
            }
            if(abstand<(amind+150) && abstand>(amind+100)){
                file.writeln("\"marker-color\": \"#ffff00\"");//gelb
            }
            if(abstand>(amind+150)){
                file.writeln("\"marker-color\": \"#46812b\"");//gruen
            }
            file.writeln("},");
            file.writeln("\"geometry\": {");
            file.writeln("\"type\": \"Point\",");
            file.writeln("\"coordinates\": [");
            file.writeln(east, ",");
            file.writeln(north);
            file.writeln("]");
            file.writeln("}");
            file.writeln("},");//Komma sollte nicht beim letzten Feature geschreiben werden, aktuell noch Fehler
        }
        zeilencount++;
    }
    file.writeln("]");
    file.writeln("}");
    return zeilencount;
}

int main(string[] args)
{
    //Alle Messdaten einlesen
    int x=0;
    string filenumber=to!string(x);
    string filename=join(["messdaten",filenumber,".txt"]);//Dateiname wird aus Text und Zahl zusammengesetzt
    while(exists(filename)){//Alle Dateien werden eingelesen, bis eine Datei mit einer entsprechenden Nummer fehlt, exists fragt, ob die Datei existiert
        readcsv(filename);//Die Datei mit dem auf Existenz geprueften Dateinamen wird eingelesen --> hier werden alle Daten verarbeitet und die Ueberholvorgaenge erkannt
        x++;//naechste Datei
        filenumber=to!string(x);//fuer Dateinamen vorbereiten
        filename=join(["messdaten",filenumber,".txt"]);//Dateinamen aus Text und Zahl zusammensetzen
    }
    if(count(current_drive.inputdata)!=0){//sollten Daten verbleiben, welche nicht durch die Unterprogrammaufrufe in readcsv verarbeitet wurden, werden diese an dieser Stelle nach dem gleichen Prinzip verarbeitet
        current_drive=automatisch_erkennen(current_drive);//gleiches UP wird aufgerufen, wie durch readcsv
        entiredata~=current_drive;//die erkannten Daten werden zu den Gesamtdaten hinzugefuegt
        destroy(current_drive);//die bisherigen Daten werden geloescht
    }

    measuredata[]overtakedata;//Daten werden in diesem Array zusammengefasst, bisher sind die Daten in entiredata noch verschachtelt, es wird ein Array erstellt
    float gesamtdistanz=0;//Insgesamt zurueckgelegte Distanz
    foreach(int i,fahrt aktuelle_fahrt;entiredata){//Daten der einzelnen Fahrten werden durchgearbeitet
        overtakedata~=aktuelle_fahrt.overtaking;//Ueberholdaten werden zusammengefasst
        gesamtdistanz=gesamtdistanz+aktuelle_fahrt.gesamtstrecke;//Insgesamt zurueckgelegte Distanz wird aus der Distanz der einzelnen Fahrten errechnet
        destroy(entiredata[i]);//aktuellen Datensatz loeschen, um Arbeitsspeicher freizugeben
    }
    writeln(gesamtdistanz);
    int intret2=writecsvfromstruct("erkannte.csv", overtakedata, false);//CSV-Datei mit allen Informationen schreiben
    int intret4=writegeojson("Geodata_overtake.geojson",overtakedata);//Alle Ueberholvorgaenge in die Geojson-Datei schreiben
    writeln(intret2,"       ",intret4);//optional

	return 0;
}
