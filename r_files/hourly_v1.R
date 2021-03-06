setwd("C:/Users/Valentin/Documents/GitHub/multi-trawl-extremes/data/")
pdbl <- read.csv("hourly_bloomsbury_2000_2017.csv")

# Reducing sample size
pdbl <- pdbl

library(evir)
library(forecast)
library(lubridate)
set.seed(42)

stlpd <- pdbl
n_vars <- length(pdbl[1,]) - 3
for(i_agent in 4:(n_vars+3)){
  fitting_matrix <- cbind(cos(2*pi*1:length(stlpd$index)/200),
                          sin(2*pi*1:length(stlpd$index)/200),
                          cos(2*pi*1:length(stlpd$index)/14),
                          sin(2*pi*1:length(stlpd$index)/14),
                          #as.numeric(isWeekend(stlpd$date)==T))
                          vapply(1:3, FUN = function(i){quarter(stlpd$date) == i}, FUN.VALUE = quarter(as.Date(stlpd$date))),
  #vapply(1:12, FUN = function(i){month(as.Date(stlpd$date)) == i}, FUN.VALUE = month(as.Date(stlpd$date))),
  vapply(1:6, FUN = function(i){wday(as.Date(stlpd$date)) == i}, FUN.VALUE = wday(as.Date(stlpd$date))),
  vapply(1:23, FUN = function(i){hour(as.Date(lubridate::hm(stlpd$time))) == i}, FUN.VALUE = wday(as.Date(stlpd$date))))
  
  fit <- lm(stlpd[,i_agent] ~ fitting_matrix)
  summary(fit)
  fitting_indices <- which(summary(fit)$coefficients[,4] < 0.05)
  if(1 %in% fitting_indices){
    fitting_indices <- fitting_indices[-1]
  }
  fitting_matrix <- fitting_matrix[,fitting_indices-1]
  print(fitting_indices)
  stlpd[,i_agent] <- lm(stlpd[,i_agent] ~ fitting_matrix)$residuals
}

q.s <- rep(0.95, n_vars) #95% everywhere
thr_stl <- rep(0, n_vars)


# WARNING
# Jittering with normals
stlpd[,-c(1:3)] <- apply(stlpd[,-c(1:3)], function(x){
  return(x + rnorm(n = length(x), mean = 0, sd = 0.1 * sd(x)))
}, MARGIN = 2)

par(mfrow=c(3,2))
for(i_agent in 4:(n_vars+3)){
  #meplot(stlpd[,i_agent])
  #print(quantile(stlpd[,i_agent], probs = c(0.7, 0.8, 0.9, 0.95, .97)))
  thr_stl[i_agent-3] <- quantile(stlpd[,i_agent], probs = q.s[i_agent-3])[[1]]
}
par(mfrow=c(1,1))

epd <- apply(as.matrix(stlpd[,-c(1:3)]), 
             FUN = function(x){
               (x - thr_stl) * (x > thr_stl)
             }, MARGIN = 1)
epd <- t(epd)
epd <- apply(X = epd, MARGIN = 2, FUN = function(x){return(x/sd(x))})

library(forecast)
# par(mfrow=c(6,2), mar=c(5.1,4.1,0.5,1.1))
# for(i_agent in 3:(n_vars+2)){
#   Acf(epd[,i_agent-2], lag.max = 40,
#       ylab=paste("ACF", colnames(epd)[i_agent-2]),
#       main="")
#   plot(epd[,i_agent-2], type="l", ylab=paste("Exceed", colnames(epd)[i_agent-2]),
#        xlab="Time")
#   #(Pacf(epd[,i_agent-2]))
# }
# par(mfrow=c(1,1))

setwd("C:/Users/Valentin/Documents/GitHub/multi-trawl-extremes/r_files/")
#source("prep_univariate_latent_trawl_fit.R")
library("evir")
s.clusters <- c(5, 5, 4, 4, 4, 4)
# val_params <- matrix(0, nrow = length(epd[1,]), ncol = 4)
# par(mfrow=c(3,2), mar=c(5.1,4.1,2.1,2.1))
# for(i_agent in 1:n_vars){
#   val_params[i_agent,] <- ev.trawl::GenerateParameters(epd[,i_agent], cluster.size = s.clusters[i_agent])
#   evir::qplot(epd[,i_agent][epd[,i_agent] > 0], xi = round(1/val_params[i_agent,1],3), labels = T, main=(colnames(epd)[i_agent]))
#   print((1+val_params[i_agent,4]/val_params[i_agent,2])^{-val_params[i_agent,1]})
# }
# par(mfrow=c(1,1))
# val_params

horizon_set <- c(1,2,3,4,5,6,12,24)
computeTRON(data = stlpd[,-c(1:3)], rep(0.95,6), horizons = horizon_set, 
            clusters = s.clusters, n_samples = 1, save = T, 'air_pollution_rerun_3')



val_pex <- findUnivariateParams(data = epd[,3:4], 
                     clusters_size = s.clusters[3:4], 
                     thresholds= rep(0, 2), 
                     optim=T, 
                     name=NA, 
                     save=T)
library(np)
BlockBootstrap <- function(exceedances, clusters, n_bootstrap, patton=F){
  n_row <- nrow(exceedances)
  
  block_length <- if(patton) 15 * np::b.star(epd[,1], round = T)[1,1] %>% as.numeric  else  5 * n_row^{2/3} %>% round
    
  boot_res <- array(dim=c(n_bootstrap, ncol(exceedances), 4))
  index_bloc <- sample(1:(n_row-block_length-1), n_bootstrap, F)
  for(index_boot in 1:n_bootstrap){
    cat('------------- BOOTSTRAP N', index_boot, '\n')
    boot_res[index_boot,,] <- findUnivariateParamsv2(data = exceedances[index_bloc[index_boot]:(index_bloc[index_boot]+block_length),] %>% as.data.frame() %>% as.matrix, 
                                                clusters_size = clusters, 
                                                thresholds= rep(0, ncol(exceedances)), 
                                                optim=T, 
                                                name=NA, 
                                                save=F)
  }
  
  return(boot_res)
}

boot_results_ap <- BlockBootstrap(epd, s.clusters, 100, T)

GetSD <- function(boostrapped_values, mc=F){
  dim_boot <- dim(boostrapped_values) # n_boot, n_vars, n_params
  n_boot <- dim_boot[1]
  n_vars <- dim_boot[2]
  n_params <- dim_boot[3]
  res <- matrix(0, nrow=n_vars, ncol=n_params)
  for(var_number in 1:n_vars){
    res[var_number,] <- apply(boostrapped_values[,var_number,], FUN = sd, MARGIN = 2)
  }
  
  if(mc){
    return(res/sqrt(n_boot))
  }else{
    return(res)  
  }
}
GetSD(boot_results_ap, mc=T)

# air_pollution_model_params <- val_p3 
# write.table(air_pollution_model_params, '~/GitHub/multi-trawl-extremes/results/air_pollution_model_params')
val_p3 <- read.table( '~/GitHub/multi-trawl-extremes/results/air_pollution_model_params')
#computeTRON(data = )



set.seed(42)
N <- 1
n.timestamps <- 5000
sim_results <- array(0, c(n_vars,N,4))

times <- 1:n.timestamps
marg.dist <- "gamma"
n <- 1
transformation <- FALSE
trawl.function <- "exp"
n_vars_sim <- 6
pb <- txtProgressBar(min = 1, max = N*n_vars_sim, style = 3, width = 50)
par(mfrow=c(6,3))
sim_res2 <- vapply(1:N,
           function(k){
             sim_episode <- vapply(1:n_vars_sim,
                                   function(i){
                                     alpha_t <- 1/val_p3[i,1]
                                     beta_t <- val_p3[i,2]/val_p3[i,1] - val_p3[i,4]
                                     kappa_t <- val_p3[i,4]
                                     #kappa_t <- 1
                                     rho_t <- val_p3[i,3]
                                     # par(mfrow=c(2,2))
                                     cat('\n proba of non-zero:', (1+kappa_t/beta_t)^{-alpha_t}, '\n')
                                     theoretical_prob_exc <- (1+kappa_t/beta_t)^{-alpha_t}
                                     sim_data <- ev.trawl::rtrawl(alpha = alpha_t, beta = beta_t, 
                                                                  kappa = 0.0, times = times, n = 1,
                                                                  marg.dist = marg.dist, rho = rho_t, 
                                                                  trawl.function = trawl.function, 
                                                                  transformation = F) # need to tweak beta and kappa
                                     sim_data_unif <- ev.trawl::rtrawl(alpha = alpha_t, beta = beta_t, 
                                                                  kappa = 0.0, times = times, n = 1,
                                                                  marg.dist = marg.dist, rho = rho_t, 
                                                                  trawl.function = trawl.function, 
                                                                  transformation = F) # need to tweak beta and kappa
                                     # used_for_probs <- vapply(1:10,
                                     #        function(x){
                                     #          return(ev.trawl::rtrawl(alpha = alpha_t, beta = beta_t, 
                                     #                                  kappa = 0.0, times = times, n = 1,
                                     #                                  marg.dist = marg.dist, rho = rho_t, 
                                     #                                  trawl.function = trawl.function, 
                                     #                                  transformation = F))
                                     #        }, rep(0, length(times)))
                                     
                                     
                                     gen_exceedances <- rep(0, length(times))
                                     
                                     unif_samples <- stats::runif(n = length(times))
                                     prob_zero <- 1 - exp(-abs(kappa_t) * sim_data)
                                     # acf(pgamma(sim_data, shape = alpha_t, rate = beta_t))
                                     # which_zero <- which((1-theoretical_prob_exc) >= pgamma(sim_data_unif, shape = alpha_t, rate = beta_t))
                                     which_zero <- which(prob_zero >= pgamma(sim_data_unif, shape = alpha_t, rate = beta_t))
                                     
                                     # for(line_index in 1:length(times)){
                                     #   # hist(prob_zero, probability = T, ylab='probability')
                                     #   # plot(prob_zero, main = 'probability being zero', 
                                     #        # ylab='probability', type='l')
                                     #   prob_zero
                                     #   which_zero <- which(prob_zero >= unif_samples)
                                     #   
                                     #   
                                     #   used_for_probs_trf <- used_for_probs
                                     #   used_for_probs_trf[which_zero,] <- 1 - exp(-abs(kappa_t) * used_for_probs[which_zero,])
                                     #   used_for_probs_trf[-which_zero,] <- exp(-abs(kappa_t) * used_for_probs[-which_zero,])
                                     #   
                                     #   used_for_probs_prod <- rbind(rep(1.0, ncol(used_for_probs_trf)),
                                     #                               used_for_probs_trf)
                                     #   used_for_probs_prod <- apply(used_for_probs_prod, MARGIN = 2, FUN = cumprod) # col-wise proba
                                     #   used_for_probs_prod <- used_for_probs_prod[-nrow(used_for_probs_prod),] # delete last row as useless
                                     #   used_for_probs_prod <- (rowSums(used_for_probs_prod * used_for_probs_trf) + 1e-8) / (rowSums(used_for_probs_prod) + 1e-8) # proba k+1
                                     #   # print(dim(used_for_probs_prod))
                                     #   print('proba conditional:')
                                     #   print(summary(used_for_probs_prod))
                                     #   print('----')
                                     #   used_for_probs_prod <- as.vector(used_for_probs_prod)
                                     #   print(length(used_for_probs_prod))
                                     #   which_zero <- which(used_for_probs_prod >= unif_samples)
                                     #   
                                     #   # print(summary(prob_zero))
                                     #   # print(summary(sim_data[-which_zero]))
                                     #   # plot(sim_data[1:(length(times)-1000)], main = 'Trawl', type='l',
                                     #        # ylab='trawl value'c
                                     # }
                                     gen_exceedances[-which_zero] <-  stats::rexp(n = length(sim_data[-which_zero]),
                                                                                  rate = sim_data[-which_zero])
                                     gen_exceedances <- gen_exceedances[1:(length(times)-1000)]
                                     cat('Prob non-zero:', length(which(gen_exceedances > 0.0))/length(gen_exceedances), '\n')
                                     print(summary(gen_exceedances[-which_zero]))
                                     acf(gen_exceedances, main = paste('Exceedances ACF', colnames(epd)[i]))
                                     points(0:10, 
                                           vapply(0:10, function(h){acf_trawl(h=h, alpha = alpha_t, 
                                                                              beta = beta_t, rho = rho_t, 
                                                                              kappa = kappa_t, delta = 0.1,
                                                                              end_seq = 80)}, 1),
                                           col = 'red', cex=1.2)
                                     lines(0:20, vapply(0:20, function(l){CountCoPositive(gen_exceedances,k=l,demean = T)/
                                         CountCoPositive(gen_exceedances,k=0,demean = T)}, 1), type='b',
                                           col = colour_palette[i], cex=2)
                                     
                                     # acf(sim_data[1:(length(times)-1000)], main = paste('Trawl ACF', colnames(epd)[i]))
                                     # points(0:10, 
                                     #        vapply(0:10, function(h){exp(-rho_t*h)}, 1),
                                     #        col = 'red', cex=1.2)
                                     
                                     # plot(gen_exceedances[1:(length(times)-1000)], main = 'Non-zero and zero exceedances',
                                     #    type='l', ylab = 'exceedances values')
                                     # plot(sim_data, main = 'Non-zero and zero trawls',
                                     #      type='l', ylab = 'exceedances values')
                                     
                                     
                                     print(eva::gpdFit(gen_exceedances[gen_exceedances>0.0], threshold = 0.0))
                                     hist(gen_exceedances[gen_exceedances>0.0], breaks = 100, probability = T)
                                     lines(0:1000/100, eva::dgpd(0:1000/100, shape=val_p3[i,1], scale = val_p3[i,2], loc = 0.0), col = 'red')
                                     
                                     hist(sim_data[1:(length(times)-1000)], probability = T, breaks=100)
                                     lines(0:1000/100, dgamma(0:1000/100, shape = alpha_t, rate = beta_t), col = 'red')
                                     
                                     setTxtProgressBar(pb, k*(i-1)+i)
                                     return(gen_exceedances)},
                                     rep(0, length(times)-1000))
                                     # return(gen_exceedances[1:(length(times)-1000)])}, 
                                     # rep(0, length(times)-1000))
             
             return(as.data.frame(sim_episode) %>% as.matrix)
           },
           matrix(0, ncol = n_vars_sim, nrow = length(times)-1000)) 

CountCoPositive <- function(x, k, proportion=T, demean=F){
  x_bis <- x[(k+1):length(x)]
  x <- x[1:(length(x)-k)]
  assertthat::are_equal(length(x), length(x_bis))
  if(proportion){
    if(demean){
      return(sum((abs(x*x_bis)> 0)) / (length(x)-k) - mean(x>0)^2)
    }else{
      return(sum((abs(x*x_bis)> 0)) / (length(x)-k))
    }
  }else{
    if(demean){
      return(sum((abs(x*x_bis)> 0))-mean(x>0)^2)
    }else{
      return(sum((abs(x*x_bis)> 0)))
    }
  }
}

library("RColorBrewer")
display.brewer.all()
colour_palette <- brewer.pal(n = 6, name = 'RdYlGn')

par(mfrow=c(1,1))
plot(0:20, vapply(0:20, function(l){CountCoPositive(sim_res2[,1,1],k=l)}/CountCoPositive(sim_res2[,i,1],k=0), 1), 
     type='b', ylab = 'Proportion of co-extremes', main = 'With Uniform from integral-transformed Gamma',
     xlab = 'k', col = colour_palette[1], cex=2, cex.lab=1.5)
i <- 1
lines(0:20, vapply(0:20, function(l){acf_trawl(l, alpha = 1/val_p3[i,1], beta = val_p3[i,2]/val_p3[i,1] - val_p3[i,4],
                                               rho = val_p3[i,3], kappa = val_p3[i,3])}, 1), type='b',
      col = colour_palette[i], cex=2, lty=4)
for(i in 2:6){
  lines(0:20, vapply(0:20, function(l){CountCoPositive(sim_res2[,i,1],k=l)/CountCoPositive(sim_res2[,i,1],k=0)}, 1), type='b',
        col = colour_palette[i], cex=2)
  lines(0:20, vapply(0:20, function(l){acf_trawl(l, alpha = 1/val_p3[i,1], beta = val_p3[i,2]/val_p3[i,1] - val_p3[i,4],
                                                 rho = val_p3[i,3], kappa = val_p3[i,3])}, 1), type='b',
        col = colour_palette[i], cex=2, lty=4)
}
legend(10, 0.05, colnames((epd)),
       text.col = colour_palette,  pch=1, lty=1, cex = 2, col = colour_palette, 
       merge = TRUE, bg = "white")

acf(sim_res2[,6,1])
lines(0:15, exp(-val_p3[6,3]*0:15))

close(pb)
acf(sim_res2[,1,1], type = 'cov')
acf(sim_episode[,1])
forecast::Acf(sim_res2[,1,1])

hist(sim_res2[,1,1][sim_res2[,1,1]>0],probability = T)
lines(0:3000/100, eva::dgpd(0:3000/100, scale=val_p3[i,2], shape = val_p3[i,1]))
CustomMarginalMLE(sim_res2[,1,1])

pb <- txtProgressBar(min = 0, max = N, style = 3, width = 50)
sim_fit <- vapply(1:N,
                  function(k){
                    sim_episode <- findUnivariateParamsv2(data =sim_res2[,,k] %>% as.data.frame %>% as.matrix, 
                                                        clusters_size = s.clusters, 
                                                        thresholds= rep(0, n_vars), 
                                                        optim=T, 
                                                        name=NA, 
                                                        save=T)
                    setTxtProgressBar(pb, k)
                    return(sim_episode)
                  },
                  matrix(0, ncol = n_vars, nrow = length(times))) 
close(pb)
for(i in 1:6){
  ev.trawl::rtrawl(alpha = 1/val_p3[i,1], beta = val_p3[i,2]/val_p3[i,1] - val_p3[i,4], 
                   kappa = 0, times = 1:1500, n = 1,
                   marg.dist = marg.dist, rho = val_p3[i,3], 
                   trawl.function = trawl.function, transformation = F)[1:1000] %>% density %>% plot
  lines(0:1000/1000, dgamma(x = 0:1000/1000, shape = 1/val_p3[i,1], rate = val_p3[i,2]/val_p3[i,1] - val_p3[i,4]))
}



for(i in 1:6){
  alpha <- 1/val_p3[i,1]
  beta <- val_p3[i,2]/val_p3[i,1]  - val_p3[i,4]
  kappa <- val_p3[i,4]
  rho <- val_p3[i,3]
  n.timestamps <- 5000
  times <- 1:n.timestamps
  
  marg.dist <- "gamma"
  n <- 1
  transformation <- FALSE
  trawl.function <- "exp"
  for(k in 1:N){
    sim_data <- rlexceed(alpha = alpha, beta = beta, kappa = kappa, rho = rho, times = times,
                   marg.dist = marg.dist, n = n, transformation = transformation,
                   trawl.function= trawl.function)
    # sim_results[i,k,] <- findUnivariateParams(data = as.matrix(sim_data),
    #                        clusters_size = s.clusters[i],
    #                        thresholds= 0,
    #                        optim=T,
    #                        name=NA,
    #                        save=T)
  }
}




n.timestamps <- 200
times <- 1:n.timestamps
kappa <- 9.591304
marg.dist <- "gamma"
n <- 1
transformation <- FALSE
trawl.function <- "exp"

trawl_sample <- ev.trawl::rtrawl(alpha = 1/0.3495718,
                   beta = 3.358772 / 0.3495718 - 9.591304,
                   #kappa = 9.591304,
                   rho = 3.51,
                   times = 1:1200/1200,
                   marg.dist = marg.dist, n = 1, transformation = transformation,
                   trawl.function= trawl.function)[1:1000]
unif_sample <- runif(1:1000/1000)

is_zero <- unif_sample < 1 - exp(-kappa * trawl_sample)
tr_sample <- rep(0, length(is_zero))
tr_sample[!is_zero] <- rexp(rate = trawl_sample, n=1)
plot(tr_sample)

# 0.8726082 1.106756 3.500629 1.272759 
# 0.6286274 1.361573 0.07887054 2.165033 
# 0.9284014 1.17611 0.09789664 1.274575 
# 1.114835 2.224347 4 1.995394 
# 0.8765932 0.9473717 0.2252814 1.083575 
# 1.0909879 1.1744739 0.05629141 1.080561

# lines 1 and 4
# 0.6328275 0.922612 1.052502 1.478699
# 0.8008777 1.370881 1.701520 1.711602

val_p <- matrix(c(
      0.3336088, 1.046199, 1.051463, 3.13539, 
      0.6328275, 0.922612, 1.052502, 1.478699,
      0.9284014, 1.17611, 0.09789664, 1.274575,
      0.741663, 2.101144, 1.701722, 2.832777, 
      0.8765932, 0.9473717, 0.2252814, 1.083575,
      1.0909879, 1.1744739, 0.05629141, 1.080561
), ncol = 6) %>% t

val_p <- val_p2
par(mfrow=c(3,2))
for(i_agent in 1:n_vars){
  # evir::qplot(epd[,i_agent][epd[,i_agent] > 0 ], xi = val_p[i_agent,1], labels = T,
  #             main=(colnames(epd)[i_agent]), threshold = 0)
  data_plot <- epd[,i_agent][epd[,i_agent] > 0]
  ll <- gpdFit(data_plot, 0.0)$par.ests
  fExtremes::qqparetoPlot(data_plot, xi = val_p2[i_agent, 1], threshold = 0.0)
  #tea::qqgpd(data = data_plot, nextremes = length(data_plot), scale=0.23, shape = 2.19)
  # print((1+val_params[i_agent,4]/val_params[i_agent,2])^{-val_params[i_agent,1]})
  # print((1+ val_p[i_agent,1] * val_p[i_agent,4]/(val_p[i_agent,2] / abs(val_p[i_agent,1]) - val_p[i_agent,4]))^{-1/val_p[i_agent,1]})
}

par(mfrow=c(3,2))
for(i_agent in 1:6){
  plot(density(epd[,i_agent][epd[,i_agent] > 0 ]))
  lines(0:15000/1000, dgpd(x = 0:15000/1000, shape = val_p[i_agent,1], scale = val_p[i_agent,2] ))
}
# TODO qqplot from 'tea' package, see docs

source("infer_latent_value.R")
epd.latent <- get.latent.values.mat(epd, val_params = val_params[,-3], randomise=F)
plot(epd.latent[,3])

### Fitting Vine Copulas

# latent
library(viridis)
library(ggplot2)
library(ggalt)

s.sample <- 2000
vars_names <- colnames(epd)
par(mfrow=c(n_vars,n_vars), mar=c(4.1,4.1,0.5,0.5))
for(i in 1:n_vars){
  for(j in 1:n_vars){
    # plot(pgamma(epd.latent[1:s.sample,i], shape = val_params[i,1], rate = val_params[i,2]),
         # pgamma(epd.latent[1:s.sample,j], shape = val_params[j,1], rate = val_params[j,2]), pch=20)
    smoothScatter(pgamma(epd.latent[1:s.sample,i], shape = val_params[i,1], rate = val_params[i,2]),
                  pgamma(epd.latent[1:s.sample,j], shape = val_params[j,1], rate = val_params[j,2]), 
                  colramp=viridis, xlab = (vars_names[i]), ylab=(vars_names[j]))
  }
}
par(mfrow=c(1,1))

s.sample <- 2000
vars_names <- colnames(epd)
par(mfrow=c(n_vars,n_vars), mar=c(4.1,4.1,0.5,0.5))
for(i in 1:n_vars){
  for(j in 1:n_vars){
    # plot(pgamma(epd.latent[1:s.sample,i], shape = val_params[i,1], rate = val_params[i,2]),
    # pgamma(epd.latent[1:s.sample,j], shape = val_params[j,1], rate = val_params[j,2]), pch=20)
    smoothScatter(epd.latent[1:s.sample,i],
                  epd.latent[1:s.sample,j], 
                  colramp=viridis, xlab = (vars_names[i]), ylab=(vars_names[j]))
  }
}
par(mfrow=c(1,1))


## CONDITIONAL TEST

s.sample <- 5001
vars_names <- colnames(epd)
par(mfrow=c(n_vars,n_vars), mar=c(4.1,4.1,0.5,0.5))
for(i in 1:n_vars){
  for(j in 1:n_vars){
    # plot(pgamma(epd.latent[1:s.sample,i], shape = val_params[i,1], rate = val_params[i,2]),
    # pgamma(epd.latent[1:s.sample,j], shape = val_params[j,1], rate = val_params[j,2]), pch=20)
    smoothScatter(pgamma(epd.latent[which(epd_cdf[2:s.sample,i] > q.s[i]), i], shape = val_params[i,1], rate = val_params[i,2]),
                  pgamma(epd.latent[which(epd_cdf[2:s.sample,i] > q.s[i]), j], shape = val_params[j,1], rate = val_params[j,2]), 
                  colramp=viridis, xlab = (vars_names[i]), ylab=(vars_names[j]))
  }
}
par(mfrow=c(1,1))


corrplot(cor(epd.latent), type = "upper", order = "hclust", 
         tl.col = "black", tl.srt = 45)

# 

p.zeroes <- 1-(1+val_params[,4]/val_params[,2])^{-val_params[,1]}
epd_cdf <- apply(X = epd, MARGIN = 1, FUN = function(x){return(plgpd.row(xs = x, p.zeroes = p.zeroes, params.mat = val_params))})
epd_cdf <- t(epd_cdf)

epd_cdf_ecdf <- epd_cdf
for(i in 1:length(epd[1,])){
  epd_cdf_ecdf[which(epd[,i]==0), i] <- ecdf(pdbl[which(epd[,i]==0), 3+i])(pdbl[which(epd[,i]==0), 3+i]) * p.zeroes[i]
}

colnames(epd_cdf_ecdf) <- colnames(epd)

library("corrplot")
par(mfrow=c(1,3))
corrplot(cor(epd_cdf), type = "upper", order = "hclust", 
         tl.col = "black", tl.srt = 45)
corrplot(cor(epd_cdf_ecdf), type = "upper", order = "hclust", method="ellipse",
         tl.col = "black", tl.srt = 45)
corrplot(cor(epd_cdf_ecdf), order = "AOE", method = "color", addCoef.col="white",
         type = "upper", tl.col = "black")
corrplot(cor(epd), type = "upper", order = "hclust", 
         tl.col = "black", tl.srt = 45)

par(mfrow=c(1,1))
corrplot(cor(epd_cdf_ecdf), order = "AOE", method = "color", addCoef.col="white",
         type = "upper", tl.col = "black")
par(mfrow=c(1,1))


s.sample <- 5000
par(mfrow=c(n_vars,n_vars), mar=c(4.1,4.1,0.5,0.5))
for(i in 1:n_vars){
  for(j in 1:n_vars){
    smoothScatter(epd_cdf[1:s.sample,j],
                  epd_cdf[1:s.sample,i],
                  colramp=viridis, xlab = (colnames(epd)[j]), ylab=(colnames(epd)[i]))
  }
}
par(mfrow=c(1,1))

vars_ordered <- c(1,2,6,5,3,4)
s.sample <- 5000
par(mfrow=c(n_vars,n_vars), mar=c(4.4,4.1,0.5,0.5))

horizon <- 12
for(i in 1:n_vars){
  for(j in 1:n_vars){
    #if(j < i){
      #plot.new()
    #}else{
    {
      data_j <- epd_cdf_ecdf[which(epd[1:(s.sample-horizon), vars_ordered[j]] > 0)+horizon, vars_ordered[j]]
      data_i <- epd_cdf_ecdf[which(epd[1:(s.sample-horizon), vars_ordered[j]] > 0)+horizon, vars_ordered[i]]
      
      data_j <- ecdf(data_j)(data_j)
      data_i <- ecdf(data_i)(data_i)
      
      
      smoothScatter(data_j, data_i,
                    colramp=inferno, xlab = (colnames(epd)[vars_ordered[j]]), ylab=(colnames(epd)[vars_ordered[i]]))  
    }
  }
}
par(mfrow=c(1,1))

### CREATION OF MATRICES
list_of_list_horizons <- list()
horizon <- c(1,2,3,6,12,24)
s.sample <- 157710
#s.sample <- 10000

for(h in horizon){
  list_of_matrices_conditional <- list()
  quantile.update.values <- matrix(0, nrow = length(epd[1,]), ncol = length(epd[1,]))
  for(i in 1:n_vars){
    mat_temp <- matrix(0,
                       nrow = length(which(epd[1:(s.sample-h), i] > 0)),
                       ncol = n_vars+1)
    temp <- epd_cdf_ecdf[which(epd[1:(s.sample-h), i] > 0), i]
    mat_temp[,n_vars+1] <- ecdf(temp)(temp)
    
    for(j in 1:n_vars){
        data_j <- epd_cdf_ecdf[which(epd[1:(s.sample-h), i] > 0)+h, j]
        quantile.update.values[i, j] <- mean(data_j <= q.s[j])
        data_j <- ecdf(data_j)(data_j)
        mat_temp[,j] <- data_j 
    }
    
    colnames(mat_temp) <- c(colnames(epd), colnames(epd)[i])
    list_of_matrices_conditional[[i]] <- mat_temp
  }
  colnames(quantile.update.values) <- colnames(epd)
  rownames(quantile.update.values) <- colnames(epd)
  
  list_of_list_horizons[[h]] <- list(unif.values=list_of_matrices_conditional,
                                     quantiles.values=quantile.update.values)
}

require(rlist)
list.save(list_of_list_horizons, file="hourly-bloomsbury-12361224.RData")

horizon <- c(1,2,3,6,12,24)
library(VineCopula)

list_of_list_horizons <- list.load(file = "hourly-bloomsbury-12361224.RData")
list_of_list_horizons_vines <- list()

for(h in horizon){
  list_of_vines_mat <- list()
  cat("Horizon: ", h, "\n")
  for(i in 1:n_vars){
    list_of_vines_mat[[i]] <- RVineStructureSelect(
                                   data = list_of_list_horizons[[h]][[i]], familyset = c(3,4), type = 0,
                                   selectioncrit = "AIC", indeptest = TRUE, level = 0.05,
                                   trunclevel = NA, progress = FALSE, weights = NA, treecrit = "tau",
                                   se = FALSE, rotations = TRUE, method = "mle", cores = 7)
    cat("--->", colnames(epd)[i], "DONE\n")
  }
  list_of_list_horizons_vines[[h]] <- list_of_vines_mat
}
list.save(list_of_list_horizons_vines, file = "hourly-bloomsbury-vines-12361224-v2.RData")

list_of_list_horizons_vines_loaded <- list.load("hourly-bloomsbury-vines-12361224-v2.RData")
list_of_list_horizons <- list.load(file = "hourly-bloomsbury-12361224.RData")

tron_probabilities <- list()
set.seed(42)
for(h in horizon){
  tron_proba_matrix <- matrix(0, nrow = length(epd[1,]), ncol = length(epd[1,]))
  colnames(tron_proba_matrix) <- colnames(epd)
  rownames(tron_proba_matrix) <- colnames(epd)
  tron_proba_matrix_sd <- tron_proba_matrix
  
  for(i in 1:n_vars){
    te.st <- RVineSim(RVM = list_of_list_horizons_vines_loaded[[h]][[i]], N = 100000)
    qq.values <- list_of_list_horizons[[h]]$quantiles.values[i,]
    qq.values <- c(qq.values, NA)
    print(qq.values)
    te.st <- t(apply(te.st, 1, function(x){x>qq.values}))
    te.st <- te.st[,1:6]
    #print(te.st)
    tron_proba_matrix[i,] <- apply(te.st, 2, mean)[1:6]
    tron_proba_matrix_sd[i,] <- (apply(te.st, 2, sd)/sqrt(length(te.st[,1])))[1:6]
  }
  tron_probabilities[[h]] <- list(mean=tron_proba_matrix, sd=tron_proba_matrix_sd)
}
tron_probabilities[[1]]$mean
tron_probabilities[[1]]$sd

list.save(tron_probabilities, file = "hourly-bloomsbury-tron-12361224.RData")

tron_probabilities_N <- list()
N_sims <- 2^(8:17)
for(h in N_sims){
  set.seed(42)
  tron_proba_matrix <- matrix(0, nrow = length(epd[1,]), ncol = length(epd[1,]))
  colnames(tron_proba_matrix) <- colnames(epd)
  rownames(tron_proba_matrix) <- colnames(epd)
  tron_proba_matrix_sd <- tron_proba_matrix
  
  for(i in 1:n_vars){
    te.st <- RVineSim(RVM = list_of_list_horizons_vines_loaded[[6]][[i]], N = h)
    qq.values <- list_of_list_horizons[[6]]$quantiles.values[i,]
    qq.values <- c(qq.values, NA)
    print(qq.values)
    te.st <- t(apply(te.st, 1, function(x){x>qq.values}))
    te.st <- te.st[,1:6]
    #print(te.st)
    tron_proba_matrix[i,] <- apply(te.st, 2, mean)[1:6]
    tron_proba_matrix_sd[i,] <- (apply(te.st, 2, sd)/sqrt(length(te.st[,1])))[1:6]
  }
  tron_probabilities_N[[h]] <- list(mean=tron_proba_matrix, sd=tron_proba_matrix_sd)
}

par(mfrow=c(1,1), mar=c(4.1,4.1,0.5,0.5))
plot(log(N_sims), log(vapply(N_sims, function(i){tron_probabilities_N[[i]]$sd[2,3]}, 1)),
     xlab="Simulations", ylab="Standard deviation")
abline( h = log(seq( -7, -2, 2^{-4})), lty = 3, col = colors()[ 440 ] )
abline( v = seq( 0, 2^18, 2^10), lty = 3, col = colors()[ 440 ] )
line(log(N_sims), log(vapply(N_sims, function(i){tron_probabilities_N[[i]]$sd[2,4]}, 1)))

axis(2, at=x,labels=x, col.axis="red", las=2)



### WORK with TRON probabilities

setwd("C:/Users/Valentin/Documents/GitHub/multi-trawl-extremes/results/MMSEV/")
for(i in 1:n_vars){
  tron_p <- round(t(vapply(1:n_vars, function(h){tron_probabilities[[horizon[h]]]$mean[i,]},
                            rep(0,n_vars))), digits = 3)
  tron_sd <- round(t(vapply(1:n_vars, function(h){tron_probabilities[[horizon[h]]]$sd[i,]},
                            rep(0,n_vars))), digits = 5)
  colnames(tron_p) <- colnames(epd)
  rownames(tron_p) <- horizon
  colnames(tron_sd) <- colnames(epd)
  rownames(tron_sd) <- horizon
  
  write.csv(tron_p, row.names = T, file = paste("tron_",colnames(epd)[i],".csv", sep = ""))
  write.csv(tron_sd, row.names = T, file = paste("tron_",colnames(epd)[i],"_sd.csv", sep = ""))
}

par(mfrow=c(2,3), mar=c(4.1,4.1,0.5,0.5))
plot(list_of_list_horizons_vines_loaded[[1]][[1]], legend.pos="bottomright", type=1, 
     interactive=F, label.bg="white", label.col="black", label.cex = 1.2, edge.lwd=1.15,
     edge.labels=c("family-par"), edge.label.cex=1.5, edge.label.col="blue")


RVineStdError(
 hessian = -RVineHessian(data = RVineSim(N = 10000, RVM = list_of_list_horizons_vines_loaded[[1]][[1]]),
               RVM = list_of_list_horizons_vines_loaded[[1]][[1]])$hessian, 
               RVM=list_of_list_horizons_vines_loaded[[1]][[1]]
  )



par(mfrow=c(n_vars,n_vars), mar=c(4.1,4.1,0.5,0.5))
for(i in 1:n_vars){
  for(j in 1:n_vars){
    data_j <- epd_cdf_ecdf[which(epd[1:(s.sample), vars_ordered[j]] > 0), vars_ordered[j]]
    data_i <- epd_cdf_ecdf[which(epd[1:(s.sample), vars_ordered[j]] > 0), vars_ordered[i]]
    
    data_j <- ecdf(data_j)(data_j)
    data_i <- ecdf(data_i)(data_i)

    if(j < i){
      plot.new()
    }else{
      smoothScatter(data_j,
                    data_i,
                    colramp=inferno, xlab = (colnames(epd)[vars_ordered[j]]), ylab=(colnames(epd)[vars_ordered[i]]))  
    }
  }
}
par(mfrow=c(1,1))

par(mfrow=c(n_vars,n_vars), mar=c(4.1,4.1,0.5,0.5))
s.sample <- 50000
for(i in 1:n_vars){
  for(j in 1:n_vars){
    data_j <- epd_cdf_ecdf[which(epd[1:s.sample, j] > 0), j]
    data_i <- epd_cdf_ecdf[which(epd[1:s.sample, j] > 0)+2, i]
    print(cor(data_i, data_j, method = "spearman"))
    min_j <- min(data_j)
    max_j <- max(data_j)
    min_i <- min(data_i)
    max_i <- max(data_i)
    smoothScatter((data_j-min_j)/(max_j-min_j),
                  (data_i-min_i)/(max_i-min_i),
                  colramp=viridis, xlab = (colnames(epd)[j]), ylab=(colnames(epd)[i]))
  }
}
par(mfrow=c(1,1))



par(mfrow=c(n_vars,n_vars), mar=c(4.1,4.1,0.5,0.5))
s.sample <- 50000
for(i in 1:n_vars){
  for(j in 1:n_vars){
    data_j <- epd_cdf_ecdf[which(epd[1:s.sample, j] > 0), j]
    data_i <- epd_cdf_ecdf[which(epd[1:s.sample, j] > 0), i]
    #print(cor(data_i, data_j, method = "spearman"))
    min_j <- min(data_j)
    max_j <- max(data_j)
    min_i <- min(data_i)
    max_i <- max(data_i)
    smoothScatter(ecdf((data_j-min_j)/(max_j-min_j))((data_j-min_j)/(max_j-min_j)),
                  ecdf((data_i-min_i)/(max_i-min_i))((data_i-min_i)/(max_i-min_i)),
                  colramp=viridis, xlab = (colnames(epd)[j]), ylab=(colnames(epd)[i]))
  }
}
par(mfrow=c(1,1))