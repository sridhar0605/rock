#' Read Manta VCF
#'
#' Read main columns of interest from Manta VCF using bcftools
#'
#' Make sure bcftools has been installed and that it can be
#' found in the R session via the PATH environmental variable.
#'
#' @param vcf Path to Manta VCF file. Can be compressed or not.
#' @return A dataframe (`tibble`) with the following fields from the VCF:
#'   * chrom1: `CHROM`
#'   * pos1: `POS` | `INFO/BPI_START`
#'   * pos2: `INFO/END` | `INFO/BPI_END`
#'   * id: `ID`
#'   * mateid: `INFO/MATEID`
#'   * svtype: `INFO/SVTYPE`
#'   * filter: `FILTER`
#'
#' @examples
#' vcf <- system.file("extdata", "HCC2218_manta.vcf", package = "pebbles")
#' rock:::read_manta_vcf(vcf)
#'
read_manta_vcf <- function(vcf) {
  stopifnot(file.exists(vcf))

  if (system("bcftools -v", ignore.stdout = TRUE) != 0) {
    stop("Oops, bcftools can't be found! Please install/add to PATH.")
  }

  if (system(paste0("bcftools view -h ",  vcf, " | grep 'BPI_START'"), ignore.stdout = TRUE) == 0) {
    message("BPI has been run on this VCF. Using INFO/BPI_START and INFO/BPI_END for coordinates")
    bcftools_query_command <- "bcftools query -f '%CHROM\t%INFO/BPI_START\t%INFO/BPI_END\t%ID\t%INFO/MATEID\t%INFO/SVTYPE\t%FILTER\n'"
  } else {
    message("BPI has not been run on this VCF. Using POS and INFO/END for coordinates")
    bcftools_query_command <- "bcftools query -f '%CHROM\t%POS\t%INFO/END\t%ID\t%INFO/MATEID\t%INFO/SVTYPE\t%FILTER\n'"
  }


  DF <- system(paste(bcftools_query_command, vcf), intern = TRUE) %>%
    tibble::tibble(all_cols = .) %>%
    tidyr::separate(col = .data$all_cols,
                    into = c("chrom1", "pos1", "pos2", "id", "mateid", "svtype", "filter"),
                    sep = "\t", convert = TRUE) %>%
    dplyr::mutate(chrom1 = as.character(.data$chrom1))


  return(DF)
}

#' Prepare Manta VCF for Circos
#'
#' Prepares a Manta VCF for display in a circos plot.
#'
#' VCF needs to be bgzipped.
#' Make sure bcftools has been installed and that it can be
#' found in the R session via the PATH environmental variable.
#'
#' @param vcf Path to bgzipped Manta VCF file. Needs to have `vcf.gz` suffix.
#' @param filter_pass Keep only variants annotated with a PASS FILTER? (default: FALSE).
#' @return A dataframe (`tibble`) with the following fields from the VCF:
#'   * chrom1: `CHROM`
#'   * pos1: `POS` | `INFO/BPI_START`
#'   * chrom2: `CHROM` (for mate2 if BND)
#'   * pos2: `INFO/END` | `INFO/BPI_END` (for mate1 if BND)
#'   * svtype: `INFO/SVTYPE`. Used for plotting.
#'
#' @examples
#' vcf <- system.file("extdata", "HCC2218_manta.vcf", package = "pebbles")
#' prep_manta_vcf(vcf)
#'
#' @export
prep_manta_vcf <- function(vcf, filter_pass = FALSE) {

  DF <- read_manta_vcf(vcf)

  # BNDs
  # We have POS of mate2 through INFO/END or INFO/BPI_END, just need CHROM.
  # Just keep first BND mates (i.e. discard duplicated information)
  # see <https://github.com/Illumina/manta/blob/master/docs/developerGuide/ID.md>
  df_bnd <- DF %>%
    dplyr::filter(.data$svtype == "BND") %>%
    dplyr::bind_cols(., .[match(.$id, .$mateid), "chrom1"]) %>%
    dplyr::rename(chrom2 = .data$chrom11) %>%
    dplyr::mutate(bndid = substring(.data$id, nchar(.data$id))) %>%
    dplyr::filter(.data$bndid == "1") %>%
    dplyr::select(.data$chrom1, .data$pos1, .data$chrom2, .data$pos2, .data$id, .data$mateid, .data$svtype, .data$filter)

  # Non-BNDs
  df_other <- DF %>%
    dplyr::filter(.data$svtype != "BND") %>%
    dplyr::mutate(chrom2 = .data$chrom1) %>%
    dplyr::select(.data$chrom1, .data$pos1, .data$chrom2, .data$pos2, .data$id, .data$mateid, .data$svtype, .data$filter)

  # All together now
  sv <- df_other %>%
    dplyr::bind_rows(df_bnd)

  if (filter_pass) {
    sv <- sv %>%
      dplyr::filter(.data$filter == "PASS")
  }

  sv <- sv %>%
    dplyr::select(.data$chrom1, .data$pos1, .data$chrom2, .data$pos2, .data$svtype)

  structure(list(sv = sv), class = "sv")
}
