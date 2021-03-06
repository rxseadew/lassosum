lassosum.pipeline <- function(cor, chr, pos, 
                              A1=NULL, A2=NULL, 
                              ref.bfile=NULL, test.bfile=NULL, 
                              LDblocks=chr, 
                              lambda=exp(seq(log(0.001), log(0.1), length.out=20)),
                              s=c(0.2, 0.5, 0.9, 1), 
                              destandardize=F, 
                              trace=1, 
                              exclude.ambiguous=TRUE, 
                              keep.ref=NULL, remove.ref=NULL, 
                              keep.test=NULL, remove.test=NULL, 
                              ...) {
  #' @title Run lassosum with standard pipeline
  #' @description The easy way to run lassosum 
  #' @param cor A vector of SNP-wise correlations with phenotype
  #'            derived from summary statistics
  #' @param chr Together with \code{pos}, chromosome and position for \code{cor}
  #' @param pos Together with \code{chr}, chromosome and position for \code{cor}
  #' @param A1 Alternative allele (effect allele) for \code{cor}
  #' @param A2 Reference allele for \code{cor} (One of \code{A1} or {A2} must be specified)
  #' @param ref.bfile \code{bfile} (\href{https://www.cog-genomics.org/plink2/formats#bed}{PLINK binary format}, without .bed) for 
  #'                  reference panel
  #' @param test.bfile \code{bfile} for test dataset
  #' @param LDblocks \code{A vector to define LD blocks}
  #' @param lambda to pass on to \code{\link{lassosum}}
  #' @param s A vector of s
  #' @param destandardize Should coefficients from \code{\link{lassosum}} be 
  #' destandardized using test dataset standard deviations before being returned?
  #' @param trace Controls the amount of output.
  #' @param exclude.ambiguous Should ambiguous SNPs (C/G, A/T) be excluded? 
  #' @param keep.ref Participants to keep from the reference panel 
  #' @param remove.ref Participants to remove from the reference panel 
  #' @param keep.test Participants to keep from the testing dataset 
  #' @param remove.test Participants to remove from the testing dataset
  #' @param ... parameters to pass to \code{\link{lassosum}}
  #' 
  #' @details To run \bold{lassosum} we assume as a minimum you have a vector of summary 
  #' statistics in terms of SNP-wise correlations (\code{cor}) and their positions (\code{chr}, 
  #' \code{pos}), one of \code{A1} or \code{A2}, and a reference panel, specified 
  #' either in \code{ref.bfile} or \code{test.bfile}. If only \code{test.bfile} is specified, 
  #' we assume \code{test.bfile} is also the \code{ref.bfile}.  
  #' If only \code{ref.bfile} is specified, only lassosum coefficients are returned, 
  #' and polygenic scores are not calculated.
  #' 
  #' If SNPwise correlations are not available, they can be converted from 
  #' p-values using the function \code{\link{p2cor}}. 
  #' 
  #' \code{lassosum.pipeline} only uses those SNPs that are consistently defined
  #' by \code{chr}, \code{pos}, \code{A1} and \code{A2} and the 
  #' \href{https://www.cog-genomics.org/plink2/formats#bim}{PLINK .bim} files
  #' specified with \code{ref.bfile} and \code{test.bfile} for estimation. 
  #' \code{\link{matchpos}} is used to achieve this, which allows for 
  #' flipping of SNP alleles in their definitions. The \code{beta} matrix in the output contains
  #' all SNPs that are common to the summary statistics and \code{test.bfile}. 
  #' However, \bold{lassosum} with \code{s} < 1 is only run on SNPs that are 
  #' common to all of \code{ref.bfile}, \code{test.bfile} and the 
  #' summary statistics. \bold{The lassosum coefficients for \code{s} < 1 are imputed with 
  #' results from \code{lassosum} with s = 1 (soft-thresholding) 
  #' run on SNPs that are common to \code{test.bfile} and the sumamry stats 
  #' but not to \code{ref.bfile}.} To select only SNPs that are common to all 
  #' three datasets, one can use the \code{also.in.refpanel} logical vector in the
  #' output. 
  #' 
  #' For \code{keep.ref}, \code{remove.ref}, \code{keep.test}, and \code{remove.test}, 
  #' see the documentation for \code{keep} and \code{remove} in \code{\link{lassosum}} 
  #' for details. 
  #' @export
  #' 
  ######################### Input validation  (start) #########################
  extensions <- c(".bed", ".bim", ".fam")
  stopifnot(!is.null(ref.bfile) || !is.null(test.bfile))
  if(!is.null(ref.bfile)) {
    for(i in 1:length(extensions)) {
      if(!file.exists(paste0(ref.bfile, extensions[i]))) {
        stop(paste0("File ", ref.bfile, extensions[i], " not found."))
      }
    }
  }
  if(!is.null(test.bfile)) {
    for(i in 1:length(extensions)) {
      if(!file.exists(paste0(test.bfile, extensions[i]))) {
        stop(paste0("File ", test.bfile, extensions[i], " not found."))
      }
    }
  } else {
    if(destandardize) stop("destandardize cannot be specified without test.bfile")
  }
  if(is.null(A1) && is.null(A2)) {
    stop("At least one of A1 (alternative allele) or A2 (reference allele) must be specified. Preferably both.")
  }

  stopifnot(!any(is.na(cor)))
  stopifnot(all(cor > -1 & cor < 1))
  stopifnot(length(chr) == length(pos))
  stopifnot(length(chr) == length(cor))
  stopifnot(is.null(A1) || length(A1) == length(cor))
  stopifnot(is.null(A2) || length(A2) == length(cor))
  chr <- as.character(sub("^chr", "", chr, ignore.case = T))

  onefile <- F  
  notest <- F
  if(is.null(ref.bfile)) {
    ref.bfile <- test.bfile
    onefile <- T
  } else {
    if(is.null(test.bfile)) {
      test.bfile <- ref.bfile
      notest <- T
      onefile <- T
    }
  }
  
  ref.bim <- fread(paste0(ref.bfile, ".bim"))
  ref.bim$V1 <- as.character(sub("^chr", "", ref.bim$V1, ignore.case = T))
  
  if(!onefile) {
      test.bim <- fread(paste0(test.bfile, ".bim"))
      test.bim$V1 <- as.character(sub("^chr", "", test.bim$V1, ignore.case = T))
  } else test.bim <- ref.bim

  if(!is.null(LDblocks)) {
    if(is.vector(LDblocks)) stopifnot(length(LDblocks) == length(cor)) else 
      if(is.data.frame(LDblocks) || is.data.table(LDblocks)) {
        LDblocks <- as.data.frame(LDblocks)
        stopifnot(ncol(LDblocks) == 3)
        stopifnot(all(LDblocks[,3] >= LDblocks[,2]))
        LDblocks[,1] <- as.character(sub("^chr", "", LDblocks[,1], ignore.case = T))
      }
  }
  s <- sort(unique(s))
  stopifnot(all(s > 0 & s <= 1))
  if(length(s) > 10) stop("I wouldn't try that many values of s.")
  ### Parse keep and remove ###
  if(notest) {
    if(!is.null(keep.test) || !is.null(remove.test)) 
      stop("keep.test and remove.test should not be specified without test.bfile.")
  }
  parsed.ref <- parseselect(ref.bfile, keep=keep.ref, remove=remove.ref)
  parsed.test <- parseselect(test.bfile, keep=keep.test, remove=remove.test)
  ref.equal.test <- identical(list(ref.bfile, keep.ref, remove.ref), 
                              list(test.bfile, keep.test, remove.test))
  ######################### Input validation  (End) #########################

  if(is.null(ref.bfile) && trace > 0) cat("Reference panel assumed the same as test data.") 

  ss <- data.frame(chr=chr, pos=pos, A1=A1, A2=A2, cor=cor)
  ### Compare summary statistics and reference panel ###
  if(trace) cat("Coordinating summary stats with reference panel...\n")
  m.ref <- matchpos(ss, ref.bim, auto.detect.ref = F, 
                    ref.chr = "V1", ref.pos="V4", ref.alt="V5", ref.ref="V6", 
                    rm.duplicates = T, exclude.ambiguous = exclude.ambiguous, 
                    silent=T)
  ss2 <- ss[m.ref$order,]
  ss2$cor <- ss2$cor * m.ref$rev
  ss2$A1 <- ref.bim$V5[m.ref$ref.extract]
  ss2$A2 <- ref.bim$V6[m.ref$ref.extract]
  
  ### Compare summary statistics and test data ###
  if(!onefile) {
    if(trace) cat("Coordinating summary stats with test data...\n")
    m.test <- matchpos(ss, test.bim, auto.detect.ref = F, 
                       ref.chr = "V1", ref.pos="V4", ref.alt="V5", ref.ref="V6", 
                       rm.duplicates = T, exclude.ambiguous = exclude.ambiguous, 
                       silent=T)
    ### Find SNPs that are common to all three datasets ###
    if(trace) cat("Coordinating summary stats, reference panel, and test data...\n")
    m.common <- matchpos(ss2, test.bim, auto.detect.ref = F, 
                         ref.chr = "V1", ref.pos="V4", 
                         ref.alt="V5", ref.ref="V6",
                         rm.duplicates = T, 
                         exclude.ambiguous = exclude.ambiguous, 
                         silent=T)
  } else {
    m.common <- m.test <- m.ref
    m.common$order <- 1:length(m.test$order)
    m.common$rev <- abs(m.common$rev)
  }

  ### Summary statistics that are common to all three datasets ###
  ss.common <- ss2[m.common$order, ]

  ### Positions of reference dataset that are common to summary statistics and test dataset ###
  ref.extract <- rep(FALSE, nrow(ref.bim))
  ref.extract[m.ref$ref.extract][m.common$order] <- TRUE
  
  ### Split data by ld region ###
  if(!is.null(LDblocks)) {
    if(is.vector(LDblocks)) {
      split <- LDblocks
    } else {
      if(trace) cat("Splitting genome by LD blocks ...\n")
      split <- splitgenome(CHR = ref.bim$V1[ref.extract], 
                           POS = ref.bim$V4[ref.extract],
                           ref.CHR = LDblocks[,1], 
                           ref.breaks = LDblocks[,3])
    }
  } else {
    split <- ref.bim$V1[ref.extract]
  }

  ### Number of different s values to try ###
  s.minus.1 <- s[s != 1]
  
  ### Get beta estimates from lassosum ###
  cor2 <- ss2$cor[sort(m.common$order)]
  if(trace) cat("Running lassosum ...\n")
  ls <- list()
  if(length(s.minus.1) > 0) {
    ls <- lapply(s.minus.1, function(s) {
      if(trace) cat("s = ", s, "\n")
      lassosum(cor=cor2, bfile=ref.bfile, 
                   shrink=s, extract=ref.extract, lambda=lambda,
                   blocks = split, trace=trace-1, 
                   keep=parsed.ref$keep, ...)
    })
  }

  ### Indeplasso ###
  ss3 <- ss[m.test$order,]
  ss3$cor <- ss3$cor * m.test$rev
  ss3$A1 <- test.bim$V5[m.test$ref.extract]
  ss3$A2 <- test.bim$V6[m.test$ref.extract]
  
  if(trace) cat("Running lassosum with s=1...\n")
  if(any(s == 1)) {
    il <- indeplasso(ss3$cor, lambda=lambda)
  } else {
    il <- list(beta=matrix(0, nrow=length(m.test$order), ncol=length(lambda)))
  }

  ### Impute indeplasso estimates to SNPs not in reference panel ###
  if(trace && any(m.test$ref.extract & !m.common$ref.extract)) 
    cat("Impute indeplasso estimates to SNPs not in reference panel ...\n")
  beta <- rep(list(il$beta), length(s))
  names(beta) <- as.character(s)
  in.refpanel <- m.common$ref.extract[m.test$ref.extract]
  re.order <- order(m.common$order)
  if(length(s.minus.1) > 0) {
    for(i in 1:length(s.minus.1)) {
      beta[[i]][in.refpanel, ] <- 
        as.matrix(Matrix::Diagonal(x=m.common$rev) %*% 
                    ls[[i]]$beta[re.order, ])
    }
  }

  ### De-standardizing correlation coefficients to get regression coefficients ###
  sd <- NULL
  if(destandardize) {
    ### May need to obtain sd ###
    if(trace) cat("Obtain standard deviations ...\n")
    sd <- rep(NA, sum(m.test$ref.extract))
    if(length(s.minus.1) > 0 && ref.equal.test) {
      # Don't want to re-compute if they're already computed in lassosum. 
      sd[in.refpanel] <- ls[[1]]$sd[re.order]
      xcl.test <- !in.refpanel
      stopifnot(all(is.na(sd[xcl.test])))
    } else {
      xcl.test <- in.refpanel & FALSE
    }
    if(any(xcl.test)) {
      toextract <- m.test$ref.extract
      toextract[toextract] <- xcl.test
      sd[xcl.test] <- sd.bfile(bfile = test.bfile, extract=toextract, 
                          keep=parsed.test$keep, ...)
    }

    if(trace) cat("De-standardize lassosum coefficients ...\n")
    ### regression coefficients = correlation coefficients / sd(X) * sd(y) ###
    sd[sd <= 0] <- Inf # Do not want infinite beta's!
    beta <- lapply(beta, function(x) as.matrix(Matrix::Diagonal(x=1/sd) %*% x))
  }
  
  ### Getting some results ###
  results <- list(beta=beta, test.extract=m.test$ref.extract, 
                  also.in.refpanel=m.common$ref.extract, 
                  sumstats=ss3, test.bfile=test.bfile, sd=sd, 
                  lambda=lambda, s=s, keep.test=parsed.test$keep, 
                  destandardized=destandardize)
  #' @return A \code{lassosum.pipeline} object with the following elements
  #' \item{beta}{A list of lassosum coefficients: one list element for each \code{s}}
  #' \item{test.extract}{A logical vector for the SNPs in \code{test.bfile} that are used in estimation.}
  #' \item{also.in.refpanel}{A logical vector for the SNPs in \code{test.bfile} that are used in \code{lassosum}.}
  #' \item{sumstats}{A \code{data.frame} of summary statistics used in estimation.}
  #' \item{test.bfile}{The testing dataset}
  #' \item{sd}{The standard deviation for the testing dataset}
  #' \item{lambda, s, keep.test, destandardized}{Information to pass on to \code{\link{validate.lassosum.pipeline}} or \code{\link{pseudovalidate.lassosum.pipeline}}}
  #' \item{pgs}{A matrix of polygenic scores}
  #' 
  
  if(notest) {
    class(results) <- "lassosum.pipeline"
    return(results) 
  }
  
  ### Polygenic scores 
  if(trace) cat("Calculating polygenic scores ...\n")
  pgs <- lapply(beta, function(x) pgs(bfile=test.bfile, weights = x, 
           extract=m.test$ref.extract, keep=parsed.test$keep))
  names(pgs) <- as.character(s)
  results <- c(results, list(pgs=pgs))
  class(results) <- "lassosum.pipeline"
  return(results) 
 
  #' @examples 
  #' ## Not run:
  #' 
  #'  ### Read ld region file ###
  #'  ld <- fread("./data/Berisa.2015.EUR.bed")
  #'  
  #'  ### Read summary statistics file ###
  #'  ss <- fread("./data/summarystats.txt")
  #'  head(ss)
  #'  
  #'  ### Convert p-values to correlations, assuming a sample size of 60000 for the p-values ###
  #'  cor <- p2cor(p = ss$P_val, n = 60000, sign=log(ss$OR_A1))
  #'  
  #'  ### Run lassosum using standard pipeline ### 
  #'  out <- lassosum.pipeline(cor=cor, chr=ss$Chr, pos=ss$Position, 
  #'                           A1=ss$A1, A2=ss$A2,
  #'                           ref.bfile=ref.bfile, test.bfile=test.bfile, 
  #'                           LDblocks = ld)
  #' ## End(**Not run**)
  
}
