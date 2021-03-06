#save(dataFrame, nrdData, crGroups, mainGroups, prdData, relData, prdData, osData, cr, dataFrameOsTD, dataFrame, osTD, tplSplitOs, groups, data, whichRFXOsTDGG, mainIdxOs, clinicalData, MultiRFX5, os, mainIdxOsTD, scope, whichRFXOsGG, file="../../code/cv100.RData")

load("cv100.RData")
library(mg14)
library(CoxHD)
library(Rcpp)
library(randomForestSRC)


jobIndex <- as.numeric(Sys.getenv("LSB_JOBINDEX"))

set.seed(jobIndex)
splits <- sample(1:nrow(dataFrame)%%5 +1 )
trainIdx <- splits!=1 ## sample 1/5

# Static models (other)
c <- coxph(os[trainIdx] ~ 1, data=dataFrame[trainIdx,mainIdxOs])
scope <- c("Genetics","CNA","Treatment","Fusions") ## For CPSS
scopeStep <- as.formula(paste("os[trainIdx] ~", paste(colnames(dataFrame)[mainIdxOs], collapse="+")))
coxBICOs <- step(c, scope=scopeStep, k = log(sum(trainIdx)), trace=0)
coxAICOs <- step(coxBICOs, scope=scopeStep, k = 2, trace=0)
coxCPSSOs <- CoxCPSSInteractions(dataFrame[!is.na(os) & trainIdx, mainIdxOs], na.omit(os[trainIdx]), bootstrap.samples=50, scope = which(groups %in% scope))
coxRFXOs <- CoxRFX(dataFrame[trainIdx,mainIdxOs], os[trainIdx], groups=groups[mainIdxOs])
coxRFXOs$Z <- NULL
coxRFXOsGGc <- CoxRFX(dataFrame[trainIdx,whichRFXOsGG], os[trainIdx], groups=groups[whichRFXOsGG], which.mu=mainGroups)
coxRFXOsGGc$Z <- NULL
rForestOsTrain <- rfsrc(Surv(time, status) ~.,data= cbind(time = os[,1], status = os[,2], dataFrame[,mainIdxOs])[trainIdx,], ntree=100, importance="none")

# Time-dependent models
trainIdxTD <- splits[tplSplitOs]!=1 ## sample 1/5
c <- coxph(osTD[trainIdxTD] ~ 1, data=dataFrameOsTD[trainIdxTD,mainIdxOsTD])
scopeStep <- as.formula(paste("osTD[trainIdx] ~", paste(colnames(dataFrameOsTD)[mainIdxOsTD], collapse="+")))
coxBICOsTD <- step(c, scope=scopeStep, k = log(sum(trainIdxTD)), trace=0)
coxAICOsTD <- step(coxBICOsTD, scope=scopeStep, k = 2, trace=0)
coxRFXOsTD <- CoxRFX(dataFrameOsTD[trainIdxTD,mainIdxOsTD], osTD[trainIdxTD], groups=groups[mainIdxOsTD])
coxRFXOsTD$Z <- NULL
coxRFXOsTDGGc <- CoxRFX(dataFrameOsTD[trainIdxTD,whichRFXOsTDGG], osTD[trainIdxTD], groups=groups[whichRFXOsTDGG], which.mu=mainGroups)
coxRFXOsTDGGc$Z <- NULL

# Multi-stage model
whichTrain <- which(trainIdx)
rfxNrs <- CoxRFX(nrdData[nrdData$index %in% whichTrain, names(crGroups)], Surv(nrdData$time1, nrdData$time2, nrdData$status)[nrdData$index %in% whichTrain], groups=crGroups, nu=ifelse(jobIndex==45,1,0), which.mu = intersect(mainGroups, unique(crGroups))) #avoiding data singularity in split 45
rfxNrs$coefficients["transplantRel"] <- 0
rfxPrs <-  CoxRFX(prdData[prdData$index %in% whichTrain, names(crGroups)], Surv(prdData$time1, prdData$time2, prdData$status)[prdData$index %in% whichTrain], groups=crGroups, nu=1, which.mu = intersect(mainGroups, unique(crGroups)))
rfxRel <-  CoxRFX(relData[relData$index %in% whichTrain, names(crGroups)], Surv(relData$time1, relData$time2, relData$status)[relData$index %in% whichTrain], groups=crGroups, which.mu = intersect(mainGroups, unique(crGroups)))
rfxRel$coefficients["transplantRel"] <- 0
rfxCr <- CoxRFX(osData[whichTrain, names(crGroups)], Surv(cr[,1], cr[,2]==2)[whichTrain], groups=crGroups, which.mu = intersect(mainGroups, unique(crGroups)), nu=ifelse(jobIndex==55,1,0))
rfxEs <- CoxRFX(osData[whichTrain, names(crGroups)], Surv(cr[,1], cr[,2]==1)[whichTrain], groups=crGroups, which.mu = NULL)
ix <- tplSplitOs %in% whichTrain
rfxOs <- CoxRFX(dataFrameOsTD[ix,whichRFXOsTDGG], osTD[ix], groups[whichRFXOsTDGG], which.mu=mainGroups) ## allow only the main groups to have mean different from zero.. 
xx <- 0:2000
coxphPrs <- coxph(Surv(time1, time2, status)~ pspline(time0, df=10), data=data.frame(prdData, time0=as.numeric(clinicalData$Recurrence_date-clinicalData$CR_date)[prdData$index])[prdData$index %in% whichTrain,]) #avoiding data singularity in split 55
tdPrmBaseline <- exp(predict(coxphPrs, newdata=data.frame(time0=xx[-1])))						
coxphOs <- coxph(Surv(time1, time2, status)~ pspline(time0, df=10), data=data.frame(osData, time0=pmin(500,cr[osData$index,1]))[osData$index %in% whichTrain,]) 
tdOsBaseline <- exp(pmin(predict(coxphOs, newdata=data.frame(time0=500)),predict(coxphOs, newdata=data.frame(time0=xx[-1])))) ## cap predictions at induction length 500 days.

dataTD <- data[tplSplitOs, ]
dataTD$transplantCR1[1:nrow(data)] <- 0
dataTD$transplantRel[1:nrow(data)] <- 0
multiRfx5 <- MultiRFX5(rfxEs, rfxCr, rfxNrs, rfxRel, rfxPrs, dataTD[!trainIdxTD,], tdPrmBaseline = tdPrmBaseline, tdOsBaseline = tdOsBaseline, x=2000)

save(rfxEs, rfxCr, rfxEs, rfxNrs, rfxPrs, rfxRel, rfxOs, multiRfx5, coxBICOs, coxBICOsTD, coxAICOs, coxAICOsTD, coxCPSSOs, coxRFXOs, coxRFXOsTD, coxRFXOsGGc, coxRFXOsTDGGc, rForestOsTrain, file=paste0("cv100/",jobIndex,".RData"))

