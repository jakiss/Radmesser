library("opencage")
apikey<-''
input <- read.csv(file='D:/6. Semester/Studienarbeit/Gesamtdate/Gesamt_2020_09_05/erkannte3.csv')
output <- data.frame(Number=c(), Distance=c(), LAT=c(), LON=c(), speed=c(), date=c(), time=c(), country=c(), state=c(), citytown=c(), postcode=c(), roadname=c(), roadtype=c(), oneway=c(), maxspeed=c(), speedin=c(), lanes=c(), bikespeed=c() )
lines<-dim(input)
print(lines[1])
oneline<-lines[1]
for(i in 1:oneline){
	dist<-input[i,1]
	time<-input[i,2]
	date<-input[i,3]
	LAT<-input[i,4]
	LON<-input[i,5]
	bikespeed<-input[i,6]
	checksum<-input[i,7]
	speed<-0
	citytown<-0
	lanes<-1
	oneway<-0
	roadtype<-0
	output1 <- opencage_reverse(latitude=LAT, longitude=LON, key=apikey,language='de')
	if(output1$rate_info$remaining>0){
		output2 <- output1$results
		country <-output2$components.country
		state <- output2$components.state
		if('components.city' %in% names(output2)){
			citytown<-output2$components.city
		}
		if('components.town' %in% names(output2)){
			citytown<-output2$components.town
		}else if('components.village' %in% names(output2)){
			citytown<-output2$components.village
		}
		postcode <- output2$components.postcode
		if('annotations.roadinfo.road' %in% names (output2)){
			roadname <- output2$annotations.roadinfo.road
		}
		if('annotations.roadinfo.road_type' %in% names(output2)){
			roadtype <- output2$annotations.roadinfo.road_type
		}
		if('annotations.roadinfo.maxspeed' %in% names(output2)){
			maxspeed <- output2$annotations.roadinfo.maxspeed
		}
		if('annotations.roadinfo.speed_in' %in% names  (output2)){
			speedin <- output2$annotations.roadinfo.speed_in
		}
		if('annotations.roadinfo.lanes' %in% names(output2)){
			lanes<-output2$annotations.roadinfo.lanes
		}
		if('annotations.roadinfo.oneway' %in% names(output2)){
			oneway<-output2$annotations.roadinfo.oneway
		}
		out <- data.frame(Number=i, Distance=dist, LAT=LAT, LON=LON, speed=speed, date=date, time=time, country=country, state=state, citytown=citytown, postcode=postcode, roadname=roadname, roadtype=roadtype, oneway=oneway, maxspeed=maxspeed, speedin=speedin, lanes=lanes, bikespeed=bikespeed )
		print(out)
		output <- rbind(output, out)
	}
}
write.csv(output, 'D:/6. Semester/Studienarbeit/Gesamtdate/Gesamt_2020_09_05/apiabfrage3.csv')