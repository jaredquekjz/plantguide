"""
Trait-Based Gardening Advisor
Based on medfate eco-physiological model principles
"""
import math
from dataclasses import dataclass
from typing import Literal, Tuple


@dataclass
class PlantTraits:
    """Core traits for gardening recommendations"""
    # Structural
    species_name: str
    growth_form: Literal["Tree", "Shrub"]
    leaf_type: Literal["Broad", "Needle", "Scale"]
    
    # Leaf economics
    sla: float  # Specific leaf area (m2/kg)
    
    # Hydraulics
    d_stem: float  # P50 - stem vulnerability (MPa)
    psi_extract: float  # Water potential at stomatal reduction (MPa)
    
    # Optional with defaults
    height: float = 300  # Plant height (cm) - default 3m
    nleaf: float = 20.0  # Leaf nitrogen content (mmol N/g dry) - default from medfate
    gswmax: float = 0.200  # Maximum stomatal conductance (mol H2O/s/m2) - default
    srl: float = 3870  # Specific root length (cm/g) - medfate default
    rlr: float = 1.0  # Root to leaf area ratio - approximate
    z95: float = 1000  # 95% rooting depth (mm)
    wood_density: float = 0.65  # g/cm3
    pi0_stem: float = -2.0  # Osmotic potential at full turgor (MPa)
    leaf_phenology: Literal["Evergreen", "Winter-deciduous", "Summer-deciduous"] = "Evergreen"


class GardeningAdvisor:
    """Generate gardening recommendations from plant traits"""
    
    def __init__(self, plant: PlantTraits):
        self.plant = plant
        
    def analyze_light_requirements(self) -> dict:
        """
        Determine light requirements using Leaf Economics Spectrum
        Based on medfate photosynthetic capacity relationships
        """
        # Calculate photosynthetic strategy
        # High SLA + High Nleaf = High photosynthetic capacity = High light
        # High SLA + Low Nleaf = Efficient light capture = Shade tolerant
        # Low SLA + Low Nleaf = Conservative = High light stress tolerant
        
        sla_category = "high" if self.plant.sla > 15 else "low"
        nleaf_category = "high" if self.plant.nleaf > 25 else "low"
        
        light_strategies = {
            ("high", "high"): {
                "requirement": "Full sun",
                "strategy": "Fast-growing acquisitive",
                "description": "Requires abundant light for rapid photosynthesis",
                "hours": "6-8+ hours direct sun"
            },
            ("high", "low"): {
                "requirement": "Partial shade to shade",
                "strategy": "Shade-adapted efficient",
                "description": "Efficiently captures scarce light with minimal investment",
                "hours": "2-4 hours direct sun or bright indirect light"
            },
            ("low", "high"): {
                "requirement": "Full sun",
                "strategy": "High-resource demanding",
                "description": "Dense leaves with high photosynthetic capacity",
                "hours": "6-8+ hours direct sun"
            },
            ("low", "low"): {
                "requirement": "Full sun (stress-tolerant)",
                "strategy": "Conservative stress-tolerant",
                "description": "Adapted to high radiation and stress conditions",
                "hours": "6-8+ hours direct sun, tolerates intense exposure"
            }
        }
        
        base_strategy = light_strategies.get((sla_category, nleaf_category))
        
        # Refine with leaf type
        if self.plant.leaf_type == "Needle" and base_strategy["requirement"] != "Full sun":
            base_strategy["notes"] = "Needle leaves suggest sun adaptation despite other traits"
            
        return base_strategy
    
    def calculate_hydraulic_safety_margin(self) -> float:
        """Calculate HSM = psi_extract - P50"""
        return self.plant.psi_extract - self.plant.d_stem
    
    def analyze_water_requirements(self) -> dict:
        """
        Comprehensive water requirement analysis
        Considers drought tolerance, water use rate, and irrigation strategy
        """
        # 1. Drought tolerance based on P50
        if self.plant.d_stem < -6.0:
            drought_tolerance = "Extremely drought tolerant"
            base_frequency = "Very rarely"
        elif self.plant.d_stem < -4.0:
            drought_tolerance = "Drought tolerant"
            base_frequency = "Infrequently"
        elif self.plant.d_stem < -2.5:
            drought_tolerance = "Moderately drought tolerant"
            base_frequency = "Regularly"
        elif self.plant.d_stem < -1.5:
            drought_tolerance = "Low drought tolerance"
            base_frequency = "Frequently"
        else:
            drought_tolerance = "Drought intolerant"
            base_frequency = "Very frequently"
        
        # 2. Water use rate based on gswmax
        if self.plant.gswmax < 0.150:
            water_use_rate = "Low water user"
            volume_modifier = 0.7
        elif self.plant.gswmax < 0.250:
            water_use_rate = "Moderate water user"
            volume_modifier = 1.0
        else:
            water_use_rate = "High water user"
            volume_modifier = 1.3
            
        # 3. Irrigation strategy based on HSM
        hsm = self.calculate_hydraulic_safety_margin()
        
        if hsm > 2.0:  # Large safety margin - isohydric
            irrigation_style = "Frequent, shallow watering"
            strategy = "Isohydric (cautious)"
            description = "Closes stomata early to avoid stress. May wilt but recovers well."
        elif hsm < 1.0:  # Small safety margin - anisohydric
            irrigation_style = "Infrequent, deep watering"
            strategy = "Anisohydric (risky)"
            description = "Continues transpiring near limits. Can suddenly collapse if too dry."
        else:
            irrigation_style = "Moderate frequency, medium depth"
            strategy = "Intermediate"
            description = "Balanced water stress response."
            
        return {
            "drought_tolerance": drought_tolerance,
            "water_use_rate": water_use_rate,
            "irrigation_frequency": base_frequency,
            "irrigation_style": irrigation_style,
            "irrigation_volume": f"{volume_modifier:.1f}x standard",
            "strategy": strategy,
            "description": description,
            "hsm": f"{hsm:.1f} MPa"
        }
    
    def analyze_soil_requirements(self) -> dict:
        """
        Soil preference analysis based on root traits and nutrient strategy
        """
        # 1. Drainage requirements based on SRL
        if self.plant.srl > 5000:  # High SRL - thin roots
            drainage = "Excellent drainage essential"
            soil_texture = "Sandy to sandy loam"
            drainage_note = "Thin roots adapted to exploring poor soils, susceptible to waterlogging"
        elif self.plant.srl > 3000:
            drainage = "Good drainage required"
            soil_texture = "Sandy loam to loam"
            drainage_note = "Moderate root thickness, prefers well-drained conditions"
        else:  # Low SRL - thick roots
            drainage = "Moderate drainage acceptable"
            soil_texture = "Loam to clay loam"
            drainage_note = "Thick roots with mycorrhizae, tolerates heavier soils"
            
        # 2. Fertility requirements based on leaf economics
        if (self.plant.sla < 10 and self.plant.nleaf > 25) or (self.plant.sla > 20 and self.plant.nleaf > 30):
            fertility = "High fertility required"
            fertilizer = "Regular feeding during growing season"
            fertility_note = "Heavy feeder requiring rich soil"
        elif self.plant.sla > 15 and self.plant.nleaf < 20:
            fertility = "Low fertility acceptable"
            fertilizer = "Minimal fertilization, may resent rich soils"
            fertility_note = "Adapted to nutrient-poor conditions"
        else:
            fertility = "Moderate fertility preferred"
            fertilizer = "Occasional feeding beneficial"
            fertility_note = "Average nutrient requirements"
            
        # 3. Soil depth and structure based on rooting
        if self.plant.z95 > 2000:  # Deep roots
            structure = "Deep, uncompacted soil essential"
            depth_note = "Deep taproot requires loose soil to >2m depth"
        elif self.plant.z95 > 1000:
            structure = "Moderately deep soil preferred"
            depth_note = "Roots explore 1-2m depth, avoid shallow hardpan"
        else:
            structure = "Can tolerate shallow soils"
            depth_note = "Shallow root system, but needs good lateral spread"
            
        # 4. pH tolerance based on osmotic potential
        if self.plant.pi0_stem < -2.5:
            ph_tolerance = "Wide pH tolerance (5.5-8.0)"
            salt_tolerance = "Moderate salt tolerance"
        else:
            ph_tolerance = "Prefers neutral pH (6.0-7.5)"
            salt_tolerance = "Salt sensitive"
            
        return {
            "drainage": drainage,
            "texture": soil_texture,
            "drainage_note": drainage_note,
            "fertility": fertility,
            "fertilizer": fertilizer,
            "fertility_note": fertility_note,
            "structure": structure,
            "depth": f"Minimum {self.plant.z95/2:.0f}mm unrestricted depth",
            "depth_note": depth_note,
            "ph": ph_tolerance,
            "salinity": salt_tolerance
        }
    
    def analyze_establishment_needs(self) -> dict:
        """
        Predict establishment difficulty based on hydraulic strategy
        Anisohydric plants are unforgiving, isohydric are forgiving
        """
        hsm = self.calculate_hydraulic_safety_margin()
        
        if hsm > 2.0:  # Large HSM - Isohydric
            difficulty = "Easy"
            forgiveness = "Forgiving"
            description = "Wilts visibly when dry, recovers well after watering"
            tips = "Watch for wilting as watering cue. Plant bounces back from mistakes."
        elif hsm < 1.0:  # Small HSM - Anisohydric  
            difficulty = "Difficult"
            forgiveness = "Unforgiving"
            description = "Shows no warning before damage. Can suddenly collapse."
            tips = "Monitor soil moisture closely. Establish irrigation before planting."
        else:
            difficulty = "Moderate"
            forgiveness = "Moderately forgiving"
            description = "Some warning signs before stress damage"
            tips = "Regular monitoring recommended during establishment"
            
        return {
            "difficulty": difficulty,
            "forgiveness": forgiveness,
            "description": description,
            "establishment_tips": tips,
            "first_year_critical": hsm < 1.5
        }
    
    def analyze_mulching_benefit(self) -> dict:
        """
        Calculate mulching benefit based on root depth and water use
        Shallow roots and high water use benefit most
        """
        # Factor 1: Root depth (shallow roots benefit more)
        if self.plant.z95 < 500:
            root_score = 3  # High benefit
        elif self.plant.z95 < 1000:
            root_score = 2  # Moderate benefit
        else:
            root_score = 1  # Low benefit
            
        # Factor 2: Water use rate + isohydric behavior
        hsm = self.calculate_hydraulic_safety_margin()
        if self.plant.gswmax > 0.25 and hsm > 2.0:
            water_score = 3  # High water use + sensitive = high benefit
        elif self.plant.gswmax > 0.20:
            water_score = 2
        else:
            water_score = 1
            
        # Combined score
        total_score = (root_score + water_score) / 2
        
        if total_score >= 2.5:
            benefit = "High"
            recommendation = "Essential - use 3-4 inch organic mulch layer"
        elif total_score >= 1.5:
            benefit = "Moderate"
            recommendation = "Beneficial - use 2-3 inch mulch layer"
        else:
            benefit = "Low"
            recommendation = "Optional - light mulch or decorative rock"
            
        return {
            "benefit_level": benefit,
            "recommendation": recommendation,
            "root_benefit": root_score,
            "water_benefit": water_score
        }
    
    def analyze_pruning_response(self) -> dict:
        """
        Predict pruning response based on growth strategy
        Acquisitive plants regrow fast, conservative plants slowly
        """
        # Determine growth strategy
        acquisitive_score = 0
        
        # High SLA = acquisitive
        if self.plant.sla > 20:
            acquisitive_score += 2
        elif self.plant.sla > 15:
            acquisitive_score += 1
            
        # High Nleaf = acquisitive
        if self.plant.nleaf > 30:
            acquisitive_score += 2
        elif self.plant.nleaf > 25:
            acquisitive_score += 1
            
        # Low wood density = fast growth
        if self.plant.wood_density < 0.4:
            acquisitive_score += 2
        elif self.plant.wood_density < 0.5:
            acquisitive_score += 1
            
        # Classify response
        if acquisitive_score >= 4:
            response = "Vigorous"
            recovery = "Fast (weeks)"
            advice = "Tolerates hard pruning. Prune to shape anytime during growing season."
        elif acquisitive_score >= 2:
            response = "Moderate"
            recovery = "Medium (months)"
            advice = "Moderate pruning ok. Time major cuts for early growing season."
        else:
            response = "Slow"
            recovery = "Slow (season to years)"
            advice = "Prune minimally. Only remove dead/damaged. Major cuts risky."
            
        return {
            "response_type": response,
            "recovery_time": recovery,
            "pruning_advice": advice,
            "acquisitive_score": acquisitive_score,
            "tolerates_hard_pruning": acquisitive_score >= 4
        }
    
    def analyze_seasonal_interest(self) -> dict:
        """
        Describe seasonal garden value based on phenology
        """
        if self.plant.leaf_phenology == "Evergreen":
            if self.plant.leaf_type == "Needle":
                winter_interest = "Excellent structure and color"
                seasonal_notes = "Year-round green backdrop. May bronze in winter."
            else:
                winter_interest = "Good structure and screening"
                seasonal_notes = "Maintains foliage year-round. New growth flush in spring."
        elif self.plant.leaf_phenology == "Winter-deciduous":
            winter_interest = "Bare structure (consider bark/form)"
            seasonal_notes = "Spring leaf emergence, summer shade, fall color potential."
        else:  # Summer-deciduous
            winter_interest = "Green in winter (unusual)"
            seasonal_notes = "Dormant in summer heat. Active growth in cool season."
            
        return {
            "phenology": self.plant.leaf_phenology,
            "winter_interest": winter_interest,
            "seasonal_notes": seasonal_notes,
            "screening_value": "Year-round" if self.plant.leaf_phenology == "Evergreen" else "Seasonal"
        }
    
    def analyze_seasonal_care_routines(self) -> dict:
        """
        Generate phenology-driven seasonal care instructions
        Based on medfate's explicit phenology modeling
        """
        phenology = self.plant.leaf_phenology
        
        care_routines = {
            "Evergreen": {
                "winter": {
                    "watering": "Minimal - only during extended dry periods",
                    "fertilizing": "None - plant metabolism slowed",
                    "pruning": "Light shaping only if needed",
                    "special": "Watch for winter desiccation in windy areas"
                },
                "spring": {
                    "watering": "Increase as new growth begins", 
                    "fertilizing": "Begin feeding when growth flush starts",
                    "pruning": "Best time for major pruning before growth",
                    "special": "Monitor for spring pest emergence"
                },
                "summer": {
                    "watering": "Maximum need - follow irrigation guidelines",
                    "fertilizing": "Continue regular feeding program",
                    "pruning": "Only light pruning to avoid stress", 
                    "special": "Mulch to conserve moisture"
                },
                "fall": {
                    "watering": "Gradually reduce as growth slows",
                    "fertilizing": "Stop feeding to encourage hardening",
                    "pruning": "Avoid - plant preparing for winter",
                    "special": "Deep watering before first freeze"
                }
            },
            "Winter-deciduous": {
                "winter": {
                    "watering": "Minimal - plant fully dormant",
                    "fertilizing": "None - no active growth",
                    "pruning": "IDEAL TIME - structural pruning when dormant",
                    "special": "Perfect for transplanting. Check for winter damage."
                },
                "spring": {
                    "watering": "Resume as buds swell, increase with leaf-out",
                    "fertilizing": "Begin feeding after leaves expand",
                    "pruning": "Finish before bud break",
                    "special": "Critical establishment period for new plantings"
                },
                "summer": {
                    "watering": "Peak demand - maintain consistent moisture",
                    "fertilizing": "Regular feeding for active growth",
                    "pruning": "Only deadheading and light shaping",
                    "special": "Monitor for summer stress"
                },
                "fall": {
                    "watering": "Reduce as leaves color and drop",
                    "fertilizing": "Stop by mid-season to allow dormancy",
                    "pruning": "Wait until fully dormant",
                    "special": "Enjoy fall color display"
                }
            },
            "Summer-deciduous": {
                "winter": {
                    "watering": "Regular - plant is actively growing!",
                    "fertilizing": "Light feeding during growth",
                    "pruning": "Shape while actively growing",
                    "special": "Unusual reversed cycle - active in cool season"
                },
                "spring": {
                    "watering": "Continue regular program",
                    "fertilizing": "Last feeding before dormancy",
                    "pruning": "Finish pruning before heat",
                    "special": "Plant preparing for summer dormancy"
                },
                "summer": {
                    "watering": "REDUCE - plant naturally dormant",
                    "fertilizing": "None - plant is resting",
                    "pruning": "None - do not disturb dormancy",
                    "special": "Natural drought defense - do not overwater!"
                },
                "fall": {
                    "watering": "Resume as temperatures cool and growth restarts",
                    "fertilizing": "Begin feeding with new growth",
                    "pruning": "Light shaping as plant reactivates",
                    "special": "Watch for rapid growth with fall rains"
                }
            }
        }
        
        care_schedule = care_routines.get(phenology, care_routines["Evergreen"])
        
        # Add water-strategy specific modifications
        hsm = self.calculate_hydraulic_safety_margin()
        if hsm < 1.0:  # Anisohydric
            for season in care_schedule.values():
                if "watering" in season:
                    season["watering"] += " - CRITICAL: Monitor closely, no drought stress!"
        
        return {
            "phenology_type": phenology,
            "seasonal_care": care_schedule,
            "key_timing": self._get_key_timing(phenology),
            "annual_cycle": self._describe_annual_cycle(phenology)
        }
    
    def _get_key_timing(self, phenology):
        """Critical timing for major garden operations"""
        timing = {
            "Evergreen": {
                "best_planting": "Early fall or early spring",
                "major_pruning": "Late winter to early spring", 
                "fertilizer_start": "Early spring growth flush",
                "fertilizer_stop": "Late summer/early fall"
            },
            "Winter-deciduous": {
                "best_planting": "Dormant season (winter)",
                "major_pruning": "Late winter when fully dormant",
                "fertilizer_start": "After leaf expansion",
                "fertilizer_stop": "Midsummer to allow hardening"
            },
            "Summer-deciduous": {
                "best_planting": "Fall as growth resumes",
                "major_pruning": "Winter during active growth",
                "fertilizer_start": "Fall with growth resumption",
                "fertilizer_stop": "Late spring before dormancy"
            }
        }
        return timing.get(phenology, timing["Evergreen"])
    
    def _describe_annual_cycle(self, phenology):
        """Describe the plant's annual cycle for gardener understanding"""
        cycles = {
            "Evergreen": "Maintains foliage year-round with growth flushes in favorable seasons",
            "Winter-deciduous": "Leafs out in spring, grows through summer, colors in fall, bare in winter",
            "Summer-deciduous": "Unique cycle: grows in cool seasons, dormant in summer heat as drought adaptation"
        }
        return cycles.get(phenology, "Standard evergreen cycle")
    
    def analyze_light_competition(self) -> dict:
        """
        Assess competitive ability and spacing needs based on medfate light competition
        Uses height, growth form, and k_par to predict competitive interactions
        """
        # Competition score based on height and growth rate
        height_score = min(3, self.plant.height / 500)  # 0-3 scale, 15m = max
        
        # k_par determines shade casting ability
        if self.plant.leaf_type == "Broad":
            k_par = 0.55  # Default broad leaf
        else:
            k_par = 0.50  # Default needle/scale
            
        shade_casting = "Heavy" if k_par > 0.7 else "Moderate" if k_par > 0.5 else "Light"
        
        # Growth rate proxy from acquisitive traits
        acquisitive_score = 0
        if self.plant.sla > 20:
            acquisitive_score += 2
        elif self.plant.sla > 15:
            acquisitive_score += 1
        if self.plant.nleaf > 30:
            acquisitive_score += 2  
        elif self.plant.nleaf > 25:
            acquisitive_score += 1
            
        # Classify competitive strategy
        if height_score > 2 and acquisitive_score >= 3:
            strategy = "Dominant Competitor"
            description = "Fast-growing and tall - will overtop neighbors quickly"
            spacing_factor = 1.5
        elif height_score > 2:
            strategy = "Structural Dominant"
            description = "Achieves dominance through height"
            spacing_factor = 1.2
        elif acquisitive_score >= 3:
            strategy = "Gap Opportunist"  
            description = "Fast growth in openings but stays shorter"
            spacing_factor = 0.8
        elif height_score < 1:
            strategy = "Understory Specialist"
            description = "Adapted to grow beneath taller plants"
            spacing_factor = 0.5
        else:
            strategy = "Moderate Competitor"
            description = "Average competitive ability"
            spacing_factor = 1.0
            
        # Calculate recommended spacing
        if self.plant.growth_form == "Tree":
            base_spacing = self.plant.height / 100 * 0.5  # meters, based on mature height
            crown_diameter = base_spacing * 0.8
        else:  # Shrub
            base_spacing = self.plant.height / 100 * 0.3
            crown_diameter = base_spacing * 1.2
            
        recommended_spacing = base_spacing * spacing_factor
        
        # Suggest compatible neighbors based on strategy
        if strategy == "Dominant Competitor":
            compatible = ["Other dominant species at wide spacing", 
                         "Understory specialists that tolerate deep shade"]
            avoid = ["Moderate competitors that need sun", "Similar height fast-growers"]
        elif strategy == "Understory Specialist":
            compatible = ["Taller structural dominants as canopy",
                         "Other shade-tolerant understory plants"]
            avoid = ["Dense fast-growing shrubs at same level"]
        else:
            compatible = ["Plants with similar competitive strategies",
                         "Complementary heights to fill vertical space"]
            avoid = ["Aggressive dominant competitors nearby"]
            
        return {
            "competitive_strategy": strategy,
            "description": description,
            "shade_casting": shade_casting,
            "k_par": k_par,
            "height_score": f"{height_score:.1f}/3.0",
            "growth_rate": "Fast" if acquisitive_score >= 3 else "Moderate" if acquisitive_score >= 1 else "Slow",
            "recommended_spacing": f"{recommended_spacing:.1f}m apart",
            "mature_crown": f"{crown_diameter:.1f}m diameter",
            "compatible_neighbors": compatible,
            "avoid_planting_near": avoid,
            "canopy_position": self._get_canopy_position()
        }
    
    def _get_canopy_position(self):
        """Determine typical canopy position based on traits"""
        if self.plant.growth_form == "Tree" and self.plant.height > 1000:
            return "Overstory/Canopy layer"
        elif self.plant.growth_form == "Tree" and self.plant.height > 500:
            return "Midstory/Subcanopy layer"
        elif self.plant.sla > 20 and self.plant.nleaf < 20:  # Shade adapted
            return "Understory layer"
        elif self.plant.growth_form == "Shrub":
            return "Shrub layer"
        else:
            return "Variable position"
    
    def analyze_shade_tolerance_nuanced(self) -> dict:
        """
        Calculate true shade tolerance by balancing photosynthetic capacity vs respiration
        Based on medfate's carbon balance approach
        """
        # Photosynthetic capacity proxy (higher Nleaf = higher Vmax)
        # But also higher respiration cost
        photo_capacity = self.plant.nleaf * 1.0  # Simplified linear relationship
        
        # Respiration cost based on Nleaf (medfate uses power functions)
        # Simplified to linear for stability
        # Lower rate for realistic shade tolerance assessment
        leaf_respiration = self.plant.nleaf * 0.05  # 5% respiration rate
        
        # Net carbon gain potential in low light
        # Shade plants can use ~60% efficiency at 10% light (medfate observation)
        low_light_photo = photo_capacity * 0.6 * 0.1  # 10% light scenario
        
        # Carbon balance in shade
        shade_carbon_balance = low_light_photo - leaf_respiration
        
        # Low-light resilience score
        if shade_carbon_balance > 0.5:
            resilience = "High"
            description = "Maintains positive carbon balance even in deep shade"
        elif shade_carbon_balance > 0:
            resilience = "Moderate"
            description = "Can survive in shade but growth limited"
        elif shade_carbon_balance > -0.5:
            resilience = "Low"
            description = "Shade survival requires excellent conditions"
        else:
            resilience = "Very Low"
            description = "Cannot maintain carbon balance in shade"
            
        # Additional factors affecting shade performance
        modifiers = []
        
        # High SLA helps light capture in shade
        if self.plant.sla > 20:
            modifiers.append("Thin leaves enhance light capture (+)")
            
        # Low Nleaf reduces respiration burden
        if self.plant.nleaf < 15:
            modifiers.append("Low respiration allows shade survival (+)")
        elif self.plant.nleaf > 30:
            modifiers.append("High respiration costs in shade (-)")
            
        # Wood density affects stem respiration
        if self.plant.wood_density < 0.4:
            modifiers.append("Low wood density reduces maintenance costs (+)")
        elif self.plant.wood_density > 0.7:
            modifiers.append("Dense wood increases carbon costs (-)")
            
        # Calculate minimum light requirement
        # Based on break-even carbon balance
        min_light_percent = max(5, (leaf_respiration / (photo_capacity * 0.6)) * 100)
        
        # Fertility requirement in shade (critical insight from sage)
        if self.plant.nleaf > 25:
            fertility_note = "CRITICAL: Requires fertile soil in shade to support high metabolism"
        elif self.plant.nleaf < 15:
            fertility_note = "Can tolerate low fertility even in shade"
        else:
            fertility_note = "Moderate fertility needed for shade survival"
            
        return {
            "low_light_resilience": resilience,
            "description": description,
            "carbon_balance_shade": f"{shade_carbon_balance:.2f}",
            "minimum_light": f"{min_light_percent:.0f}% of full sun",
            "shade_modifiers": modifiers,
            "fertility_in_shade": fertility_note,
            "shade_strategy": self._classify_shade_strategy(),
            "placement_advice": self._get_shade_placement_advice(resilience, min_light_percent)
        }
    
    def _classify_shade_strategy(self):
        """Classify shade adaptation strategy"""
        if self.plant.sla > 20 and self.plant.nleaf < 20:
            return "True shade specialist - efficient light use"
        elif self.plant.sla > 15 and self.plant.nleaf < 25:
            return "Shade tolerant - balanced approach"
        elif self.plant.nleaf > 30:
            return "Sun plant - shade intolerant due to high respiration"
        else:
            return "Intermediate - prefers partial shade"
            
    def _get_shade_placement_advice(self, resilience, min_light):
        """Specific advice for shade placement"""
        if resilience == "High":
            return "Excellent for deep shade areas, north walls, dense tree cover"
        elif resilience == "Moderate":
            return f"Best in bright shade or {min_light:.0f}% filtered sun"
        elif resilience == "Low":
            return "Only morning shade or very brief afternoon shade"
        else:
            return "Requires full sun - shade will cause decline"
    
    def generate_complete_guide(self) -> dict:
        """Generate comprehensive gardening recommendations"""
        light = self.analyze_light_requirements()
        water = self.analyze_water_requirements()
        soil = self.analyze_soil_requirements()
        
        # New detailed analyses
        establishment = self.analyze_establishment_needs()
        mulching = self.analyze_mulching_benefit()
        pruning = self.analyze_pruning_response()
        seasonal = self.analyze_seasonal_interest()
        
        # Enhanced analyses from sage's wisdom
        seasonal_care = self.analyze_seasonal_care_routines()
        competition = self.analyze_light_competition()
        shade_tolerance = self.analyze_shade_tolerance_nuanced()
        
        # Additional integrated recommendations
        garden_placement = self._recommend_garden_placement(light, water, soil)
        companion_traits = self._suggest_companion_traits(water, soil)
        
        return {
            "species": self.plant.species_name,
            "light_requirements": light,
            "water_requirements": water,
            "soil_requirements": soil,
            "establishment": establishment,
            "mulching": mulching,
            "pruning": pruning,
            "seasonal_interest": seasonal,
            "seasonal_care": seasonal_care,
            "competition_spacing": competition,
            "shade_tolerance_detailed": shade_tolerance,
            "garden_placement": garden_placement,
            "companion_suggestions": companion_traits
        }
    
    def _recommend_garden_placement(self, light, water, soil):
        """Suggest optimal garden placement"""
        placements = []
        
        # Light-based placement
        if "Full sun" in light["requirement"]:
            placements.append("South-facing exposure")
        elif "shade" in light["requirement"].lower():
            placements.append("North side of structures or under tree canopy")
            
        # Water-based placement
        if "Very rarely" in water["irrigation_frequency"]:
            placements.append("Xeriscape or rock garden")
        elif "Very frequently" in water["irrigation_frequency"]:
            placements.append("Near water feature or in irrigated border")
            
        # Drainage-based placement
        if "Excellent drainage" in soil["drainage"]:
            placements.append("Raised beds or slopes")
        elif "clay loam" in soil["texture"]:
            placements.append("Level ground or rain garden edges")
            
        return placements
    
    def _suggest_companion_traits(self, water, soil):
        """Suggest traits for companion plants"""
        companions = {
            "similar_water": f"Plants with P50 near {self.plant.d_stem:.1f} MPa",
            "similar_strategy": water["strategy"].split()[0] + " water strategy plants",
            "similar_soil": f"Plants preferring {soil['texture']}",
            "complementary": []
        }
        
        # Suggest complementary companions
        if self.plant.growth_form == "Tree":
            companions["complementary"].append("Shade-tolerant understory shrubs")
        if self.plant.srl > 4000:
            companions["complementary"].append("Deep-rooted plants to avoid competition")
            
        return companions


def create_garden_examples():
    """Create examples for common garden plants"""
    
    examples = {
        "Tomato (Solanum lycopersicum)": PlantTraits(
            species_name="Tomato (Solanum lycopersicum)",
            growth_form="Shrub",  # Herbaceous but shrub-like
            leaf_type="Broad",
            height=150,  # 1.5m typical
            sla=25.0,  # Very high - thin leaves
            nleaf=35.0,  # Very high - fast growth
            d_stem=-1.8,  # Low drought tolerance
            psi_extract=0.5,  # Closes stomata early
            gswmax=0.35,  # High water use
            srl=2800,  # Low - thick roots
            z95=600,  # Shallow roots
            wood_density=0.3  # Very low - herbaceous
        ),
        
        "Hosta": PlantTraits(
            species_name="Hosta",
            growth_form="Shrub",  # Herbaceous perennial
            leaf_type="Broad",
            height=60,  # 60cm typical height
            sla=20.0,  # High - thin shade leaves
            nleaf=15.0,  # Low - shade adapted
            d_stem=-1.2,  # Very drought sensitive
            psi_extract=-0.8,  # Close to failure point
            gswmax=0.12,  # Low - conservative in shade
            srl=4200,  # Moderate-high
            z95=400,  # Very shallow
            wood_density=0.25  # Very low
        ),
        
        "Rosemary": PlantTraits(
            species_name="Rosemary",
            growth_form="Shrub",
            leaf_type="Needle",
            height=120,  # 1.2m typical
            sla=5.0,  # Very low - thick needles
            nleaf=14.0,  # Low - conservative
            d_stem=-6.5,  # Extremely drought tolerant
            psi_extract=-2.8,  # Conservative stomatal control
            gswmax=0.14,  # Low water use
            srl=6000,  # High - efficient roots
            z95=1200,  # Moderate depth
            wood_density=0.55,
            pi0_stem=-3.0  # Very high osmotic adjustment for salt tolerance
        ),
        
        "Maple Tree (Acer)": PlantTraits(
            species_name="Maple Tree (Acer)",
            growth_form="Tree",
            leaf_type="Broad",
            height=1500,  # 15m mature height
            sla=12.0,  # Moderate
            nleaf=28.0,  # High - deciduous strategy
            d_stem=-2.34,  # Angiosperm deciduous default
            psi_extract=-1.24,  # Moderate (HSM = 1.1)
            gswmax=0.22,  # Moderate
            srl=2500,  # Low - mycorrhizal
            z95=2000,  # Deep roots
            wood_density=0.52,
            leaf_phenology="Winter-deciduous"
        )
    }
    
    return examples


def print_gardening_guide(species_name, traits, advisor, guide):
    """Print formatted gardening guide"""
    print(f"\nGARDENING GUIDE FOR {species_name}")
    print(f"{'='*60}")
    
    # Light requirements
    light = guide["light_requirements"]
    print(f"\n📍 LIGHT REQUIREMENTS:")
    print(f"   Requirement: {light['requirement']}")
    print(f"   Strategy: {light['strategy']}")
    print(f"   Details: {light['description']}")
    
    # Water requirements  
    water = guide["water_requirements"]
    print(f"\n💧 WATER REQUIREMENTS:")
    print(f"   Drought tolerance: {water['drought_tolerance']} (P50: {traits.d_stem:.1f} MPa)")
    print(f"   Water use rate: {water['water_use_rate']} (gswmax: {traits.gswmax:.2f})")
    print(f"   Irrigation: {water['irrigation_style']}")
    print(f"   Frequency: {water['irrigation_frequency']}")
    print(f"   Volume: {water['irrigation_volume']}")
    print(f"   Strategy: {water['strategy']} (HSM: {water['hsm']})")
    
    # Soil requirements
    soil = guide["soil_requirements"] 
    print(f"\n🌱 SOIL REQUIREMENTS:")
    print(f"   Drainage: {soil['drainage']}")
    print(f"   Texture: {soil['texture']}")
    print(f"   Fertility: {soil['fertility']}")
    print(f"   Structure: {soil['structure']}")
    print(f"   pH: {soil['ph']}")
    
    # Establishment
    establishment = guide["establishment"]
    print(f"\n🌿 ESTABLISHMENT:")
    print(f"   Difficulty: {establishment['difficulty']} ({establishment['forgiveness']})")
    print(f"   Description: {establishment['description']}")
    print(f"   Tips: {establishment['establishment_tips']}")
    
    # Mulching
    mulching = guide["mulching"]
    print(f"\n🍂 MULCHING:")
    print(f"   Benefit: {mulching['benefit_level']}")
    print(f"   Recommendation: {mulching['recommendation']}")
    
    # Pruning
    pruning = guide["pruning"]
    print(f"\n✂️ PRUNING:")
    print(f"   Response: {pruning['response_type']}")
    print(f"   Recovery: {pruning['recovery_time']}")
    print(f"   Advice: {pruning['pruning_advice']}")
    
    # Seasonal interest
    seasonal = guide["seasonal_interest"]
    print(f"\n🍁 SEASONAL INTEREST:")
    print(f"   Phenology: {seasonal['phenology']}")
    print(f"   Winter interest: {seasonal['winter_interest']}")
    print(f"   Notes: {seasonal['seasonal_notes']}")
    
    # Seasonal care routines (NEW)
    seasonal_care = guide["seasonal_care"]
    print(f"\n📅 SEASONAL CARE CALENDAR:")
    print(f"   Annual cycle: {seasonal_care['annual_cycle']}")
    print(f"   Key timing:")
    for operation, timing in seasonal_care['key_timing'].items():
        print(f"     {operation}: {timing}")
    
    # Competition and spacing (NEW)
    competition = guide["competition_spacing"]
    print(f"\n🌲 COMPETITION & SPACING:")
    print(f"   Strategy: {competition['competitive_strategy']}")
    print(f"   Description: {competition['description']}")
    print(f"   Growth rate: {competition['growth_rate']}")
    print(f"   Spacing: {competition['recommended_spacing']}")
    print(f"   Mature crown: {competition['mature_crown']}")
    print(f"   Canopy layer: {competition['canopy_position']}")
    
    # Shade tolerance details (NEW)
    shade = guide["shade_tolerance_detailed"]
    print(f"\n🌙 SHADE TOLERANCE ANALYSIS:")
    print(f"   Low-light resilience: {shade['low_light_resilience']}")
    print(f"   Minimum light needs: {shade['minimum_light']}")
    print(f"   {shade['description']}")
    print(f"   {shade['fertility_in_shade']}")
    if shade['shade_modifiers']:
        print(f"   Modifiers:")
        for mod in shade['shade_modifiers']:
            print(f"     • {mod}")


if __name__ == "__main__":
    # Generate guides for common garden plants
    garden_examples = create_garden_examples()
    
    for species_name, traits in garden_examples.items():
        advisor = GardeningAdvisor(traits)
        guide = advisor.generate_complete_guide()
        print_gardening_guide(species_name, traits, advisor, guide)