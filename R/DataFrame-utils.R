### =========================================================================
### DataFrame utilities
### -------------------------------------------------------------------------

### - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
### Splitting and combining.
###

setMethod("split", "DataFrame",
          function(x, f, drop = FALSE) {
            CompressedList("CompressedSplitDataFrameList", x, splitFactor = f)
          })

setMethod("cbind", "DataFrame",
          function(..., deparse.level=1) {
            ans <- DataFrame(...)
            elementMetadata(ans) <-
              do.call(rbind, lapply(list(...), elementMetadata))
            ans
          })

setMethod("rbind", "DataFrame", function(..., deparse.level=1) {
  args <- list(...)
  hasrows <- unlist(lapply(args, nrow), use.names=FALSE) > 0
  hascols <- unlist(lapply(args, ncol), use.names=FALSE) > 0

  if (!any(hasrows | hascols)) {
    return(DataFrame())
  } else if (!any(hasrows)) {
    return(args[[which(hascols)[1]]])
  } else if (sum(hasrows) == 1) {
    return(args[[which(hasrows)]])
  } else {
    args <- args[hasrows]
  }

  xdf <- args[[1]]

  for (i in 2:length(args)) {
    if (ncol(xdf) != ncol(args[[i]]))
      stop("number of columns for arg ", i, " do not match those of first arg")
    if (!identical(colnames(xdf), colnames(args[[i]])))
      stop("column names for arg ", i, " do not match those of first arg")
  }

  if (ncol(xdf) == 0) {
    ans <- DataFrame()
    ans@nrows <- sum(unlist(lapply(args, nrow), use.names=FALSE))
  } else {
    cn <- colnames(xdf)
    cl <- unlist(lapply(as.list(xdf, use.names = FALSE), class))
    factors <- unlist(lapply(as.list(xdf, use.names = FALSE), is.factor))
    cols <- lapply(seq_len(length(xdf)), function(i) {
      cols <- lapply(args, `[[`, cn[i])
      if (factors[i]) { # combine factor levels, coerce to character
        levs <- unique(unlist(lapply(cols, levels), use.names=FALSE))
        cols <- lapply(cols, as.character)
      }
      combined <- do.call(c, cols)
      if (factors[i])
        combined <- factor(combined, levs)
      ## this coercion needed only because we extracted ([[) above
      ## which brings external -> internal
      ## external objects should support external combination (c)
      as(combined, cl[i])
    })
    names(cols) <- colnames(xdf)
    ans <- do.call(DataFrame, cols)
  }

  rn <- unlist(lapply(args, rownames), use.names=FALSE)
  if (!is.null(rn)) {
    if (length(rn) != nrow(ans)) {
      rn <- NULL
    } else if (any(duplicated(rn)))
      rn <- make.unique(rn)
  }
  rownames(ans) <- rn

  ans
})