# This allocates tows (or anything really) for a straified random design.  
#This can be based on bottom type (or another polygon based non-continuous stratifying variable)
#####  DK August 26th, 2016
# Update history
# Commented, checked  and revised by DK August 2016 (Added in seed option to the function)


#####################################  Function Summary ########################################################
####  
##  This function is used within these files:(a.k.a "dependent files") 
# 1: source(paste(direct_fns,"Survey_design/Survey_design_test.r",sep=""))
###############################################################################################################

###############################################################################################################
## This function needs these functions to work (a.k.a. "support files")
# 1:   source(paste(direct_fns,"Survey_design/genran.r",sep=""))
# 2:   source(paste(direct_fns,"Maps/ScallopMap.r",sep=""))
###############################################################################################################



###############################################################################################################
# Arguments
# poly.lst:       The bank survey, if there is a stratified survey this includes all these data.  A second list is required with this that contains
#                 the survey information for the bank.  format required is poly.lst = list(survey_detail_polygon,survey_information)
# bounding.poly:  The boundary polygon for the bank.  
# ntows:          The number of tows on the bank.  If there are repeat tows this is total number - number of repeats.  Default is missing
# bank.plot:      Do you want to make a bank.plot.  T/F, default = F,
# mindist:        The minimum distance between points.  Default = 1, this is used in genran and if repeated tows to weed out tows too close to each other
# pool.size:      What size is the pool you are pulling from.  Essentially this is multiplier to give larger pools for random allocation.  Default = 4
# repeated.tows:  Are their repeated tows.  Default = NULL.  A dataframe with a list of the repeated tows (EID, X,Y, stratum are required columns)
# lplace:         If making a plot where to put the legend.  Default ='bottomleft'
# show.pool:      Plot the entire pool of randomly generated points.  T/F default = F
# seed:           Set a seed so that your results can be reproduced.  Default = NULL which uses R random number generation.  Any integer will result
#                 in producing a reproducable random number draw.
# repo:           Where are the functions you need for this.  Default = 'github' which points to the github repo and latest stable versions of the functions
#                 Alternative is to specify the directory the function exists, something like "D:/Github/Offshore/Assessment_fns/DK/" to get to the folders with this files in them
###############################################################################################################



alloc.poly<-function(poly.lst,bounding.poly,ntows,bank.plot=F,mindist=1,pool.size=4,
                     repeated.tows=NULL,lplace='bottomleft',show.pool=F,seed = NULL,repo = 'github')
{
	require(PBSmapping) || stop("You'll need to install PBSmapping if you wanna do this thang")
  
  if(repo != 'github')
  {
    source(paste(repo,"Survey_design/genran.r",sep=""))
    source(paste(repo,"Maps/ScallopMap.r",sep=""))
  } # end if(repo != 'github')
  
  if(repo == 'github')
  {
    funs <- c("https://raw.githubusercontent.com/Mar-Scal/Assessment_fns/master/Survey_design/genran.r",
              "https://raw.githubusercontent.com/Mar-Scal/Assessment_fns/master/Maps/ScallopMap.r")
    # Now run through a quick loop to load each one, just be sure that your working directory is read/write!
    for(fun in funs) 
    {
      download.file(fun,destfile = basename(fun))
      source(paste0(getwd(),"/",basename(fun)))
      file.remove(paste0(getwd(),"/",basename(fun)))
    } # end for(un in funs)
  } # end if(repo == 'github')

  # This ignores all warnings
	options(warn=-1)
	# create pool of random points, if we haven't specified the number of points the second element of the poly list needs to have an allocation table in
  # it so we can figure out the total number of tows.
	if(missing(ntows)) ntows<-sum(poly.lst[[2]]$allocation)
	# This tells use the number of pools, which is simply the total number of tows multiplied by the "pool.size", the higher we set pool.size the
	# more location that are generated by genran, later we will sample from this large number of potential sites and narrow it down to the 
	# appropriate number of locations.
	npool=ntows*pool.size
	
	# If the bounding polygon is specified make this surveyed.polys object
	# DK Note, I don't really think this surveyed.polys object is necessary anymore since in all cases it is simply poly.lst[[1]]...
	# Also, we are now handling this differently than Brad does in his github function so we should keep our eye on 
	# how we handle this bounding.poly bit of code.
	if(!missing(bounding.poly)) surveyed.polys<-poly.lst[[1]]

	# If the bounding polygon is missing you'll need to make it yourself based on the supplied polydata
	if(missing(bounding.poly))
	{
	  # Get the poly data
	  surveyed.polys<-poly.lst[[1]]
	  # Using the points in the polyset detmine the shape of the polygon using the convex hull
	  bounding.poly<-poly.lst[[1]][chull(poly.lst[[1]]$X,poly.lst[[1]]$Y),]
		# Now make up the position and secondary ID's needed for PBSmapping
	  bounding.poly$POS<-1:nrow(bounding.poly)
		bounding.poly$SID<-1
	} # end if(missing(bounding.poly))
	# Make the bounding.poly a PBS projection for Latitude/longitude
	attr(bounding.poly,"projection")<-"LL"
	
	# Now generate a large number of random points within this survey boundary polygon.
	# This retuns the tow ID, X & Y coordinates and the nearest neighbour distance.
	#source(paste(direct_fns,"Survey_design/genran.r",sep=""))
	pool.EventData <- genran(npool,bounding.poly,mindist=mindist,seed=seed)
	
	# Make a Poly ID object for each unique strata
	Poly.ID<-unique(poly.lst[[2]]$PID)
	# Grab the strata names
	strata<-as.character(unique(poly.lst[[2]]$PName))
	# Define a variable
	strataTows.lst<-NULL
	
	# if the allocation scheme is provided in the second element of the poly.lst use it to calculate the strata area
	if("allocation" %in% names(poly.lst[[2]]))
	{
	  # Get the allocation for each strata
		towsi<-with(poly.lst[[2]],tapply(allocation,PName,unique))
		# Combine the survey boundary with the Poly ID and strata name then make it a "LL" PBSmapping object
		strataPolys.dat<-merge(surveyed.polys,subset(poly.lst[[2]],select=c("PID","PName")))
		attr(strataPolys.dat,"projection")<-"LL"
		# Now calculate the strata Area for the polygons using only the Primary Polygon ID's
		strataArea<-calcArea(strataPolys.dat,1)
	} # end if("allocation" %in% names(poly.lst[[2]]))
	
	# if the allocation scheme hasn't been provided then you'll need to run this.
	else
	{
		# initialize some variables.
		strataPolys.lst<-NULL
		strataArea<-c()
		towsi<-c()
		
		# calculate area and proportional allocation
		for(i in 1:length(strata))
		{
		  # Get the strata Polygon ID's (names)
			strataPIDS<-poly.lst[[2]]$PID[poly.lst[[2]]$PName==strata[i]]
			# Create a temporary variable which is the surveyed.polygons that are part of the current strata.
			tmp <- surveyed.polys[surveyed.polys$PID %in% strataPIDS,]
			# If the surveyed polygon has a PID that is in the current strata run this
			if(nrow(tmp)>0)
			{
			  # Give the strata a name in the temp object
				tmp$PName<-strata[i]
				# This will combine polygons into one large polygon then make that a PBSmapping object
				strataPolys.lst[[i]]<-combinePolys(tmp)
				attr(strataPolys.lst[[i]],"projection")<-"LL"
				# Calculate the area of this strata
				strataArea[i]<-calcArea(strataPolys.lst[[i]],1)$area
				# Give it it's proper name
				names(strataArea)[i]<-strata[i]
				print(strata[i]) # print this name to the screen
			} # end if(nrow(tmp)>0)
		} # end for(i in 1:length(strata))
		
		# Remove NA's
		strataArea<-na.omit(strataArea)
		# Turn the strataPolys.lst into a data.frame
		strataPolys.dat<-do.call("rbind",strataPolys.lst)
		# Get the number of tows for each strata and round to nearest whole number
		towsi<-round(strataArea/sum(strataArea)*ntows)
		# Keep only the results for strata that have tows
		towsi<-towsi[towsi>0]
		# This is needed to correct for rounding error, the first strata will get more/less tows by maybe 1 or 2 depending on how the rounding occured
		towsi[1]<-ntows-sum(towsi[-1])
		# Get the names for the strata that have tows.
		strata<-names(towsi)
	} # end else
	
	# For the strata with tows 
	for(i in 1:length(strata))
	{
	  # Get tows generated in the genran function that are found within the current strata, this creates more tows then are allocated to a strata 
	  # these are then subset to the appropriate number of tows in the next step
		LocSet<-findPolys(pool.EventData,subset(strataPolys.dat,PName==strata[i]))
		# Create the final list of tows, this is a subset of the tows created by genran based on the allocation scheme calculated for towsi.
		strataTows.lst[[i]]<-data.frame(subset(pool.EventData,EID %in% LocSet$EID)[1:towsi[strata[i]],c("EID","X","Y")],Poly.ID=poly.lst[[2]]$PID[poly.lst[[2]]$PName==strata[i]],STRATA=strata[i])
	} # end for(i in 1:length(strata))
	# Unwrap the strata tows list into a dataframe
	Tows<-do.call("rbind",strataTows.lst)
	# Give each tow an unique ID
	Tows$EID<-1:sum(towsi)
	# Have the rownames match the EID and then make the Tows object a PBSmapping object
	rownames(Tows)<-1:sum(towsi)
	attr(Tows,"projection")<-"LL"
	
	# If there are repeated tows this will randomly select stations from last years	survey (repeated.tows)
	if(!is.null(repeated.tows))
	{
		# Define a new variable
	  repeated.lst<-NULL
	  # Reset the names for the repeated tows
		names(repeated.tows)<-c("EID","X","Y","Poly.ID")
		# Give the tows from last year (repeated tows) a unique number
		repeated.tows$EID<-repeated.tows$EID+1000
		# Get the info for the repeats that you entered as part of poly.lst
		repeat.str<-poly.lst[[2]][!is.na(poly.lst[[2]]$repeats),]
		# Combine this tows selected for this year with repeated tows and make that a PBSmapping object
		tmp <- rbind(Tows[,-5],repeated.tows)
		attr(tmp,"projection")<-"LL"
		# Calculate the nearest neighbour distance
		# The Lat/Lon's  for both the temp and bounding poly are converted to UTM coordinates, and a window ia around these coordiantes is made (owin)
		# For the points within this window the nearest neighbour calculations are then made and tacked onto the tmp object
		tmp$nndist <- nndist(as.ppp(subset(convUL(tmp),select=c('X','Y')),with(convUL(bounding.poly),owin(range(X),range(Y)))))
		# Potential repeated tows are then selected that are > mindist from each other.
		repeated.tows<-subset(tmp,nndist > mindist & EID>1000,-5)
		# We now get repeats from each strata (for German Bank there is no strata so i =1)
		for(i in 1:length(repeat.str$PID))
	  {
		  # Get the tows that are in the correct strata
			str.tows<-subset(repeated.tows,Poly.ID==repeat.str$PID[i]) 
			nrow(str.tows)
			# Now from these repeat tows grab the appropriate number of tows. Note that if we want this sample reproducible we need to set the seed again
			#(Should be fine to just have this above in a function, but if running line by line you'll need this)
			if(!is.null(seed)) set.seed(seed)
			repeated.lst[[i]] <- str.tows[sample(1:nrow(str.tows),repeat.str$repeats[repeat.str$PID==repeat.str$PID[i]]),]
			# Add the strata name column
			repeated.lst[[i]]$STRATA<-repeat.str$PName[repeat.str$PID==repeat.str$PID[i]]
		} # end for(i in 1:length(repeat.str$PID))
    # Unwrap the list into a dataframe
		repeated.tows<-do.call("rbind",repeated.lst)
		# Combine the tows into a list with the new tows and a list with the repeats.
		Tows<-list(new.tows=Tows, repeated.tows=repeated.tows)
	} # end if(!is.null(repeated.tows))

	# If you want to make the bank plot 
	if(bank.plot==T)
	{
    #	source(paste(direct_fns,"Maps/ScallopMap.r",sep=""))
    # Make the plot
	  ScallopMap(bank.plot,poly.lst=list(surveyed.polys,poly.lst[[2]]))
		# Make a background color for the points
	  bg.col<-tapply(poly.lst[[2]]$col,poly.lst[[2]]$PName,unique)
		# If there are no repeated tows do this
	  if(is.null(repeated.tows))addPoints(Tows,pch=21, cex=1,bg=bg.col[as.character(Tows$STRATA)])
		# if there are repeated tows add them
	  if(!is.null(repeated.tows))
		{
			addPoints(Tows$new.tows,pch=21, cex=1,bg=bg.col[as.character(Tows$new.tows$STRATA)])
			addPoints(Tows$repeated.tows,pch=24, cex=1,bg=bg.col[as.character(Tows$repeated.tows$STRATA[order(Tows$repeated.tows$EID)])])
		} # end if(!is.null(repeated.tows))
	  # If we want to show the results directly from the genran function which will show the entire pool of randomly generated points accross the bank.
		if(show.pool==T) addPoints(pool.EventData,pch=4,cex=0.4)
		# Add the appropriate legend to the figure.
	  if(!is.null(repeated.tows))legend(lplace,legend=names(bg.col[unique(as.character(Tows$new.tows$STRATA))]),pch=21,
		                                  pt.bg=bg.col[unique(as.character(Tows$new.tows$STRATA))],bty='n',cex=1, inset = .02)
	  
		if(is.null(repeated.tows))legend(lplace,legend=names(bg.col[unique(as.character(Tows$STRATA))]),pch=24,
		                                 pt.bg=bg.col[unique(as.character(Tows$STRATA))],bty='n',cex=1, inset = .02)

	} # end if(bank.plot ==T)
	
	# Turn the warnings back on.
	options(warn=0)
	# Return the results to the function calling this.
	return(list(Tows=Tows,Areas=strataArea))
	
} # end function

