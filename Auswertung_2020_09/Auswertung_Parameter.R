input <- read.csv(file='D:/6. Semester/Studienarbeit/apiabfrage.csv')
print(input[,3])
input[,3]<-input[,3]-45
hist(input[,3])
speed<-100
input2<-input [(input$maxspeed==speed),]
input2<-input [(input$roadtype=="living_street"),]
lines<-dim(input2)
print(lines)
mean(input$Distance)
hist(input[,3],
	xlab="Überholabstand in cm",
	ylab="Zahl der Überholvorgänge",
	xlim=c(0,250),
	main="Überholabstand")