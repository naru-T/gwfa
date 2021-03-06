gwfa <- function(sdata,elocat, vars,bw,k=2, kernel, adaptive=TRUE, p=2, theta=0, longlat=FALSE, dMat=NULL,
                  n.obs = NA, n.iter=1, rotate="oblimin", scores="regression",
                  residuals=FALSE, SMC=TRUE, covar=FALSE,missing=FALSE,impute="median",
                  min.err = 0.001,  max.iter = 50,symmetric=TRUE, warnings=TRUE, fm="minres",
                  alpha=.1,pr=.05,oblique.scores=FALSE,np.obs=NULL,use="pairwise",cor="cor",
                  correct=.5,weight=NULL, timeout, foreach=FALSE, organize=FALSE,...) {


##This function is based on GWmodel::gwpca and psych::fa
  requireNamespace("GWmodel")
  requireNamespace("psych")
  requireNamespace("R.utils")
  requireNamespace("foreach")
  #requireNamespace("doMC")
  requireNamespace("doParallel")

  mae <- function(x){sum(abs(x)/length(x))}
  
  if (is(sdata, "Spatial")) {
    p4s <- proj4string(sdata)
    dp.locat <- coordinates(sdata)
  }
  else if (is(sdata, "data.frame") && (!missing(dMat)))
    data <- sdata
  else stop("Given data must be a Spatial*DataFrame or data.frame object")
  
  if (missing(elocat)) {
    ep.given <- FALSE
    elocat <- coordinates(sdata)
  }
  else {
    ep.given <- T
    if (is(elocat, "Spatial")) {
      espdf <- elocat
      elocat <- coordinates(espdf)
    }
    else if (is.numeric(elocat) && dim(elocat)[2] == 2)
      elocat <- elocat
    else {
      warning("Output loactions are not packed in a Spatial object,and it has to be a two-column numeric vector")
      elocat <- dp.locat
    }
  }
  data <- as(sdata, "data.frame")
  dp.n <- nrow(data)
  ep.n <- nrow(elocat)
  if (missing(dMat)) {
    DM.given <- F
    DM1.given <- F
    if (dp.n + ep.n <= 10000) {
      dMat <- gw.dist(dp.locat = dp.locat, rp.locat = elocat,
                      p = p, theta = theta, longlat = longlat)
      DM.given <- T
    }
  }
  else {
    DM.given <- T
    DM1.given <- T
    dim.dMat <- dim(dMat)
    if (dim.dMat[1] != dp.n || dim.dMat[2] != ep.n)
      stop("Dimensions of dMat are not correct")
  }
  if (missing(vars))
    stop("Variables input error")
  if (missing(bw) || bw <= 0)
    stop("Bandwidth is not specified incorrectly")
  len.var <- length(vars)
  col.nm <- colnames(data)
  var.idx <- match(vars, col.nm)[!is.na(match(vars, col.nm))]
  if (length(var.idx) == 0)
    stop("Variables input doesn't match with data")
  x <- data[, var.idx]
  x <- as.matrix(x)
  var.nms <- colnames(x)
  var.n <- ncol(x)
  if (len.var > var.n)
    warning("Invalid variables have been specified, please check them again!")

  
  if(organize==TRUE){
    fit.fa <- psych::fa(r=data, nfactors=k, scores=scores, fm=fm, rotate=rotate, oblique.scores=oblique.scores)
  }
  
  if(foreach == TRUE){
    
      cl <- makeCluster(detectCores())
      registerDoParallel(cl)
       
      out <- foreach(i= 1:ep.n) %dopar% {
        #for (i in 1:ep.n) {
        
        score.all <-  matrix(NA,ep.n,k)
        
        if (DM.given)
          dist.vi <- dMat[, i]
        else {
          if (ep.given)
            dist.vi <- GWmodel::gw.dist(dp.locat, elocat, focus = i,
                               p, theta, longlat)
          else dist.vi <- GWmodel::gw.dist(dp.locat, focus = i, p = p,
                                  theta = theta, longlat = longlat)
        }
        wt <- GWmodel::gw.weight(dist.vi, bw, kernel, adaptive)
        use <- wt > 0
        wt <- wt[use]
        if (length(wt) <= 5) {
          expr <- paste("Too small bandwidth at location: ",
                        i)
          warning(paste(expr, "and the results can't be given there.",
                        sep = ", "))
          next
        }
        
        temp <- gwefa::wfa(x=data[use, ], wt, factors=k, scores=scores, n.obs = length(wt), fm=fm, rotate=rotate, oblique.scores=oblique.scores, timeout=timeout)
        
        
        if(is.null(temp)){
          load <- matrix(NA, ncol=k, nrow=var.n)
          #score.all <- matrix(NA, ncol=k, nrow=dp.n)
          s <- rep(NA, k)
          u <- rep(NA, var.n)
          ld<- rep(NA, k)
          ss <- rep(NA, k)
          #cortemp <- NA
          cor.mt <- rep(NA, gamma(k))
          resid_sqsum <- NA
          rmsea <- NA
          
        } else {
          
          if(organize==TRUE){
            
            colnm <- sapply( 1:k, function(x){apply((fit.fa$loadings - temp$loadings[,x]),2,mae) %>% which.min()})
            
          }else{
            colnm <- colnames(temp$scores) 
          }
          
          load <- matrix(temp$loadings[, order(colnm)], ncol=k, nrow=var.n)
          score.all[use, ] <- temp$scores[, order(colnm)]
          ld<- temp$Vaccounted[1,order(colnm)]
          ss <- temp$Vaccounted[2,order(colnm)]
          cortemp <- cor(temp$scores[,order(colnm)])
          s <- score.all[i,]
          u <- temp$uniquenesses
          cor.mt <- cortemp[upper.tri(cortemp)] #correlation between factor scores
          resid_sqsum <- sum(temp$residual[upper.tri(temp$residual)]^2, na.rm=TRUE)
          rmsea <- temp$RMSEA[1]
        }
        
        list(
          loadings=load,
          score=s,
          uniquenesses=u,
          loading_score=ld,
          residuals_sqsum = resid_sqsum,
          ss=ss,
          cor.mt=cor.mt,
          rmsea=rmsea)
        
      }
      
      stopCluster(cl)
   
      loadings = array(as.numeric(unlist(lapply(out,"[[","loadings"))), dim=c(c(var.n,k,ep.n))) %>% aperm(.,  c(3,1,2))
      
      
    res <- list(
      # loadings = lapply(out,"[[","loadings") %>% unlist()
      loadings = array(as.numeric(unlist(lapply(out,"[[","loadings"))), dim=c(c(var.n,k,ep.n))) %>% aperm(.,  c(3,1,2)),
      score = t(sapply(out,"[[", 'score')),
      uniquenesses = t(sapply(out,"[[","uniquenesses")),
      loading_score = t(sapply(out,"[[","loading_score")),
      residuals_sqsum = t(sapply(out,"[[","residuals_sqsum")) %>% as.numeric(),
      ss = t(sapply(out,"[[","ss")),
      cor.mt = t(sapply(out,"[[","cor.mt")),
      rmsea = t(sapply(out,"[[","rmsea")) %>% as.numeric()
    )
    
  } else{
  load <- array(NA,c(ep.n,var.n,k))
  resid_sqsum <- rep(NA, nrow(elocat))
  s <- matrix(NA,ep.n,k)
  u <- matrix(NA,ep.n,var.n)
  ld <- matrix(NA,ep.n,k)
  ss <- matrix(NA,ep.n,k)
  cor.mt <- matrix(NA,ep.n,sum(seq(1,(k-1),1)))
  rmsea <- rep(NA, nrow(elocat))
  score.all <-  matrix(NA,ep.n,k)

  for (i in 1:ep.n) {

    if (DM.given)
      dist.vi <- dMat[, i]
    else {
      if (ep.given)
        dist.vi <- gw.dist(dp.locat, elocat, focus = i,
                           p, theta, longlat)
      else dist.vi <- gw.dist(dp.locat, focus = i, p = p,
                              theta = theta, longlat = longlat)
    }
    wt <- gw.weight(dist.vi, bw, kernel, adaptive)
    use <- wt > 0
    wt <- wt[use]
    if (length(wt) <= 5) {
      expr <- paste("Too small bandwidth at location: ",
                    i)
      warning(paste(expr, "and the results can't be given there.",
                    sep = ", "))
      next
    }

    temp <- wfa(x=data[use, ], wt, factors=k, scores=scores, n.obs = length(wt), fm=fm, rotate=rotate, oblique.scores=oblique.scores, timeout=timeout)
    
    if(is.null(temp)){
      load[i,,] <- matrix(NA, ncol=k, nrow=var.n)
      score.all[use, ] <- rep(NA, k)
      #s[i,] <- NA
      u[i,] <- rep(NA, var.n)
      ld[i,]<- rep(NA, k)
      ss[i,] <- rep(NA, k)
      #cortemp <- NA
      cor.mt[i,] <- rep(NA, gamma(k))
      resid_sqsum[i] <- NA
      rmsea[i] <- NA

    } else {

      if(organize==TRUE){
        
        colnm <- sapply( 1:k, function(x){apply((fit.fa$loadings - temp$loadings[,x]),2,mae) %>% which.min()})
        
      }else{
        colnm <- colnames(temp$scores) 
      }
      
      
      load[i,,] <- matrix(temp$loadings[, order(colnm)], ncol=k, nrow=var.n)
      score.all[use, ] <- temp$scores[, order(colnm)]
      s[i,] <- score.all[i,]
      u[i,] <- temp$uniquenesses
      ld[i,]<- temp$Vaccounted[1,order(colnm)]
      ss[i,] <- temp$Vaccounted[2,order(colnm)]
      cortemp <- cor(temp$scores[,order(colnm)])
      cor.mt[i,] <- cortemp[upper.tri(cortemp)] #correlation between factor scores
      resid_sqsum[i] <- sum(temp$residual[upper.tri(temp$residual)]^2, na.rm=TRUE)
      rmsea[i] <- temp$RMSEA[1]
      
    }
  }
  dimnames(load)[[3]] <- colnames(temp$loadings)[order(colnames(temp$loadings))]
  
  
 res <- list(
        loadings=load,
        score=s,
        uniquenesses=u,
        loading_score=ld,
        residuals_sqsum = resid_sqsum,
        ss=ss,
        cor.mt=cor.mt,
        rmsea=rmsea)
  }
  
  return(res)
  
}
