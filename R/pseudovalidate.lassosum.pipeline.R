pseudovalidate.lassosum.pipeline <- function(ls.pipeline, test.bfile=NULL, 
                                       keep=NULL, remove=NULL, 
                                       trace=1, 
                                       destandardize=F, plot=T, 
                                       exclude.ambiguous=T, ...) {
  #' @title Function to perform pseudovalidation from a lassosum.pipeline object
  #' @param ls.pipeline A lassosum.pipeline object
  #' @param test.bfile The (\href{https://www.cog-genomics.org/plink2/formats#bed}{PLINK bfile} for the test dataset 
  #' @param keep Participants to keep (see \code{\link{lassosum}} for more details)
  #' @param remove Participants to remove
  #' @param trace Controls amount of output
  #' @param destandardize Should coefficients from \code{\link{lassosum}} be 
  #' destandardized using test dataset standard deviations before being returned?
  #' @param plot Should the validation plot be plotted? 
  #' @param exclude.ambiguous Should ambiguous SNPs (C/G, A/T) be excluded? 
  #' @param ... parameters to pass to \code{\link{pseudovalidation}}
  #' @details Pseudovalidation is explained in Mak et al (2016). It helps 
  #' choosing a value of \code{lambda} and \code{s} in the absence of a validation
  #' phenotype. 
  #' @export
  installed <- installed.packages()[,1]
  if(!("fdrtool" %in% installed)) 
    stop("Pseudovalidation requires fdrtool. Please install from CRAN.")
  
  stopifnot(class(ls.pipeline) == "lassosum.pipeline")

  results <- list(lambda=ls.pipeline$lambda, s=ls.pipeline$s)
  
  if(!is.null(keep) || !is.null(remove)) if(is.null(test.bfile)) 
    stop("Please specify test.bfile if you specify keep or remove")
  
  redo <- T
  if(is.null(test.bfile)) {
    test.bfile <- ls.pipeline$test.bfile
    keep <- ls.pipeline$keep.test
    remove <- NULL
    redo <- F
  }
  
  if(destandardize) {
    if(ls.pipeline$destandardized) stop("beta in ls.pipeline already destandardized.")
    sd <- sd.bfile(test.bfile, extract=ls.pipeline$test.extract, 
                   keep=keep, remove=remove, ...)
    sd[sd <= 0] <- Inf # Do not want infinite beta's!
    ls.pipeline$beta <- lapply(ls.pipeline$beta, 
                   function(x) as.matrix(Matrix::Diagonal(x=1/sd) %*% x))
    redo <- T
  }
  
  if(redo) {
    ### Input Validation ### 
    extensions <- c(".bed", ".bim", ".fam")
    for(i in 1:length(extensions)) {
      if(!file.exists(paste0(test.bfile, extensions[i]))) {
        stop(paste0("File ", test.bfile, extensions[i], " not found."))
      }
    }
    ### Input Validation (end) ### 
    
    if(trace) cat("Coordinating lassosum output with test data...\n")
    
    bim <- fread(paste0(test.bfile, ".bim"))
    bim$V1 <- as.character(sub("^chr", "", bim$V1, ignore.case = T))
    
    m <- matchpos(ls.pipeline$sumstats, bim, auto.detect.ref = F, 
                  ref.chr = "V1", ref.pos="V4", ref.alt="V5", ref.ref="V6", 
                  rm.duplicates = T, exclude.ambiguous = exclude.ambiguous, 
                  silent=T)
    
    beta <- lapply(ls.pipeline$beta, function(x) 
      as.matrix(Matrix::Diagonal(x=m$rev) %*% x[m$order, ]))
    if(trace) cat("Calculating PGS...\n")
    toextract <- m$ref.extract
    pgs <- lapply(beta, function(x) pgs(bfile=test.bfile, weights = x, 
                                        extract=toextract, 
                                        keep=keep, remove=remove))
    names(pgs) <- as.character(ls.pipeline$s)
    results <- c(results, list(pgs=pgs))
    
  } else {
    toextract <- ls.pipeline$test.extract
    if(is.null(ls.pipeline$pgs)) {
      if(trace) cat("Calculating PGS...\n")
      pgs <- lapply(ls.pipeline$beta, function(x) pgs(bfile=test.bfile, 
                                                      weights = x, 
                                                      keep=keep))
      names(pgs) <- as.character(ls.pipeline$s)
      results <- c(results, list(pgs=pgs))
    } else {
      results <- c(results, list(pgs=ls.pipeline$pgs))
    }
    
  } 
  
  ### Pseudovalidation ###
  lambdas <- rep(ls.pipeline$lambda, length(ls.pipeline$s))
  ss <- rep(ls.pipeline$s, rep(length(ls.pipeline$lambda), length(ls.pipeline$s)))
  PGS <- do.call("cbind", results$pgs)
  BETA <- do.call("cbind", ls.pipeline$beta)
  
  if(trace) cat("Estimating local fdr ...\n")
  fdr <- fdrtool::fdrtool(ls.pipeline$sumstats$cor, statistic="correlation", 
                          plot=F)
  cor.shrunk <- ls.pipeline$sumstats$cor * (1 - fdr$lfdr)
  if(trace) cat("Performing pseudovalidation ...\n")
  pv <- pseudovalidation(test.bfile, 
                         beta=BETA, 
                         cor=cor.shrunk, 
                         extract=toextract, 
                         keep=keep, remove=remove,
                         sd=ls.pipeline$sd, ...)
  if(plot) {
    plot(lambdas, pv, log="x", col=as.factor(ss), type="o", 
         xlab="lambda", ylab="Pseudovalidation")
    legend(x="topright", col=1:length(ls.pipeline$s), pch=1, 
           legend=paste0("s=", ls.pipeline$s))
  }

  pv[is.na(pv)] <- -Inf
  best <- which(pv == max(pv))[1]
  best.s <- ss[best]
  best.lambda <- lambdas[best]
  best.pgs <- PGS[,best]
  validation.table <- data.frame(lambda=lambdas, s=ss, value=pv)
  results <- c(results, list(best.s=best.s, 
                             best.lambda=best.lambda,
                             best.pgs=best.pgs, 
                             validation.table=validation.table))
  return(results)
  
}

